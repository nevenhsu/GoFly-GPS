import AppKit
import SwiftUI
import GoFlyMacCore

struct MacRootView: View {
    @Bindable var model: MacAppModel
    @State private var splashDelayFinished = false

    var body: some View {
        Group {
            switch model.route {
            case .startup:
                if splashDelayFinished { LaunchScreen(model: model) }
                else { GoFlyStyle.canvas }
            case .environment(let step):
                MacEnvironmentScreen(model: model, step: step)
            case .environmentSummary:
                MacEnvironmentSummaryScreen(model: model)
            case .deviceList:
                DeviceListScreen(model: model)
            case .deviceDetail:
                MacDeviceDetailScreen(model: model)
            case .install:
                if let setup = model.setup { MacInstallScreen(model: model, setup: setup) }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(GoFlyStyle.canvas)
        .foregroundStyle(GoFlyStyle.ink)
        .font(GoFlyStyle.font(14))
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            if model.route == .startup { splashDelayFinished = true }
        }
        .onChange(of: splashDelayFinished) { _, shown in
            if shown, model.route == .startup {
                Task { await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "E00") }
            }
            if shown, model.route == .deviceList {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if model.route == .deviceList {
                        await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "D01")
                    }
                }
            }
        }
        .onChange(of: model.route) { _, route in
            if route == .deviceList {
                Task { await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "D01") }
            } else if route == .deviceDetail, model.devicePageState == .restartRequired {
                Task { await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "D14") }
            }
        }
        .onChange(of: model.setup?.hasUnfinishedTransaction) { _, unfinished in
            if unfinished == true { model.openInterruptedSetup() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.route != .startup { model.checkEnvironment() }
        }
    }
}

private struct LaunchScreen: View {
    @Bindable var model: MacAppModel

    private var damagedBundle: Bool {
        guard let failure = model.failure else { return false }
        return failure == .bundleInvalid || failure == .unavailable || failure == .service("bundle-damaged")
    }

    var body: some View {
        if damagedBundle {
            Text("GoFly 無法啟動，請重新安裝")
                .font(GoFlyStyle.font(15))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MacColorSystem.brandMarkSurface)
                    .frame(width: 112, height: 112)
                    .overlay { DesignAsset("WingedArrow", width: 68, tint: MacColorSystem.brandMark) }
                    .padding(.bottom, 24)
                Text("GoFly").font(GoFlyStyle.font(32, bold: true))
                Text("for Mac").font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted).padding(.top, 2)
                if model.failure == nil {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(GoFlyStyle.line.opacity(0.55))
                            Capsule().fill(GoFlyStyle.ink).frame(width: geometry.size.width * 0.7)
                        }
                    }
                    .frame(width: 100, height: 5)
                    .padding(.top, 22)
                    Text("正在檢查 Mac 環境…")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted).padding(.top, 16)
                } else {
                    Text("無法完成檢查")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted).padding(.top, 24)
                    Button("重新檢查") { model.beginLaunchCheck() }
                        .buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoFlyStyle.canvas)
        }
    }
}

private struct DeviceListScreen: View {
    @Bindable var model: MacAppModel

    var body: some View {
        HStack(spacing: 0) {
            MacDeviceSidebar(model: model)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(MacLocalization.text("device.crumb")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        Text(MacLocalization.text("device.d01.title"))
                            .font(GoFlyStyle.font(28, bold: true)).padding(.top, 10)
                        Text(MacLocalization.text("device.d01.subtitle"))
                            .font(GoFlyStyle.font(15)).foregroundStyle(GoFlyStyle.muted).padding(.top, 5)
                        if model.visibleDevices.isEmpty {
                            emptyDeviceCard.padding(.top, 30)
                        } else {
                            deviceRows.padding(.top, 30)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                deviceFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoFlyStyle.canvas)
        }
        .background(GoFlyStyle.canvas)
        .onAppear {
            #if DEBUG
            Task { await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "D01") }
            #endif
        }
    }

    private var emptyDeviceCard: some View {
        VStack(spacing: 0) {
            instructionRow("1", title: MacLocalization.text("device.d01.step1"))
            Rule()
            instructionRow("2", title: MacLocalization.text("device.d01.step2"), detail: MacLocalization.text("device.d01.step2.detail"))
            Rule()
            instructionRow("3", title: MacLocalization.text("device.d01.step3"))
        }
        .background(GoFlyStyle.sidebar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("device-connect-instructions")
    }

    private func instructionRow(_ number: String, title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(GoFlyStyle.font(15)).frame(width: 12, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(GoFlyStyle.font(15))
                if let detail { Text(detail).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 15.2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceRows: some View {
        VStack(spacing: 0) {
            ForEach(model.visibleDevices, id: \.connectionID) { device in
                Button {
                    model.openDevice(device)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone").font(.system(size: 22)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.displayName).font(GoFlyStyle.font(15, bold: true))
                            Text(device.connectionName).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(GoFlyStyle.muted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).goFlyRowFocus()
                if device.connectionID != model.visibleDevices.last?.connectionID { Rule() }
            }
        }
        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var deviceFooter: some View {
        HStack {
            Spacer()
            Button {} label: {
                Text(MacLocalization.text("device.d01.waiting")).font(GoFlyStyle.font(13, bold: true))
                    .foregroundStyle(GoFlyStyle.muted)
                    .frame(width: 140, height: 36)
                    .background(GoFlyStyle.secondarySurface, in: Capsule())
            }
            .buttonStyle(.plain).disabled(true)
                .accessibilityIdentifier("device-waiting")
        }
        .padding(.horizontal, 48).frame(height: 80)
        .overlay(alignment: .top) { Rule() }
    }
}

enum CaptureScreenshotHelper {
    @MainActor
    static func captureIfRequested(expectedScreen: String) async {
        #if DEBUG
        guard let info = Bundle.main.infoDictionary,
              let directory = info["GoFlyCaptureOutput"] as? String,
              let screen = info["GoFlyCaptureScreen"] as? String,
              screen == expectedScreen,
              let appearance = info["GoFlyCaptureAppearance"] as? String else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard let content = NSApp.windows.first(where: \.isVisible)?.contentView else { return }
        content.displayIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let file = folder.appendingPathComponent("\(screen)-\(appearance).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("Unable to save GoFly capture screenshot: %@", String(describing: error))
        }
        #endif
    }
}
