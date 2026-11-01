import SwiftUI
import GoFlyMacCore

private func deviceText(_ key: String) -> String { MacLocalization.text(key) }

struct MacDeviceDetailScreen: View {
    @Bindable var model: MacAppModel

    var body: some View {
        HStack(spacing: 0) {
            MacDeviceSidebar(model: model)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        pageContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoFlyStyle.canvas)
        }
        .background(GoFlyStyle.canvas)
        .accessibilityIdentifier("device-detail-\(model.devicePageState.accessibilityKey)")
    }

    private var state: MacDevicePageState { model.devicePageState }
    private var device: ConnectedDevice? { model.selected }

    private var deviceBreadcrumb: String {
        guard let device else { return deviceText("device.crumb") }
        switch state {
        case .trustRequired, .developerModeRequired, .readyToInstall, .restartRequired: break
        default: return deviceText("device.crumb")
        }
        return String(format: deviceText("device.crumb.selected"), device.displayName)
    }

    private var titleKey: String {
        switch state {
        case .noDevice: "device.d01.title"
        case .chooseDevice: "device.choose.title"
        case .checking: "device.checking.title"
        case .inspectRequired: "device.inspect.title"
        case .trustRequired: "device.d02.title"
        case .developerModeRequired: "device.d03.title"
        case .readyToInstall: "device.d04.title"
        case .installed: device?.displayName ?? deviceText("device.d08.title.fallback")
        case .updateAvailable: device?.displayName ?? deviceText("device.d08.title.fallback")
        case .wifiNeedsUSB: device?.displayName ?? deviceText("device.d12.title.fallback")
        case .wifiUnavailable:
            String(format: deviceText("device.d13.title.format"), device?.displayName ?? deviceText("device.d13.title.fallback"))
        case .restartRequired:
            deviceText(model.setup?.mode == .renew ? "device.d14.renew.title" : "device.d14.install.title")
        }
    }

    private var subtitleKey: String? {
        switch state {
        case .trustRequired: "device.d02.subtitle"
        case .developerModeRequired: "device.d03.subtitle"
        case .readyToInstall: "device.d04.subtitle"
        case .installed: "device.d08.subtitle"
        case .updateAvailable: "device.d09.subtitle"
        case .wifiNeedsUSB: "device.d12.subtitle"
        case .wifiUnavailable: "device.d13.subtitle"
        case .restartRequired: "device.d14.subtitle"
        case .noDevice, .chooseDevice, .checking, .inspectRequired: nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(deviceBreadcrumb)
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            Text(titleKey.hasPrefix("device.") ? deviceText(titleKey) : titleKey)
                .font(GoFlyStyle.font(28, bold: true)).padding(.top, 8)
            if let subtitleKey {
                Text(deviceSubtitle(subtitleKey))
                    .font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            } else if state == .checking {
                Text(deviceText("device.checking.subtitle"))
                    .font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted).padding(.top, 5)
            }
        }
        .padding(.bottom, state == .trustRequired || state == .developerModeRequired ? 24 : 26)
    }

    @ViewBuilder private var pageContent: some View {
        switch state {
        case .noDevice:
            emptyDeviceCard
        case .chooseDevice:
            MessageCard(icon: "iphone", title: deviceText("device.choose.body"), kind: .neutral)
        case .checking:
            MessageCard(icon: "arrow.triangle.2.circlepath", title: deviceText("device.checking.body"), kind: .neutral, showsProgress: true)
        case .inspectRequired:
            MessageCard(icon: "exclamationmark.circle", title: failureMessage, kind: .warning)
        case .trustRequired:
            preparationPage(developerMode: false)
        case .developerModeRequired:
            preparationPage(developerMode: true)
        case .readyToInstall:
            readyToInstallPage
        case .installed:
            installedPage(isUpdate: false)
        case .updateAvailable:
            installedPage(isUpdate: true)
        case .wifiNeedsUSB:
            wifiUSBPage
        case .wifiUnavailable:
            wifiUnavailablePage
        case .restartRequired:
            restartRequiredPage
        }
    }

    private var emptyDeviceCard: some View {
        VStack(spacing: 0) {
            D01InstructionRow(number: "1", title: deviceText("device.d01.step1"))
            DeviceRule().padding(.leading, 52)
            D01InstructionRow(number: "2", title: deviceText("device.d01.step2"), detail: deviceText("device.d01.step2.detail"))
            DeviceRule().padding(.leading, 52)
            D01InstructionRow(number: "3", title: deviceText("device.d01.step3"))
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("device-connect-instructions")
    }

    private func preparationPage(developerMode: Bool) -> some View {
        HStack(alignment: .top, spacing: 132) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    preparationRow(number: nil, title: "device.prep.usb", status: .complete)
                    DeviceRule().padding(.leading, 54)
                    preparationRow(number: nil, title: "device.prep.trust",
                                   detail: developerMode ? nil : "device.prep.trust.detail",
                                   status: developerMode ? .complete : .current)
                    DeviceRule().padding(.leading, 54)
                    preparationRow(number: "3", title: "device.prep.developer",
                                   detail: developerMode ? "device.prep.developer.detail" : nil,
                                   status: developerMode ? .current : .pending)
                    DeviceRule().padding(.leading, 54)
                    preparationRow(number: "4", title: "device.prep.install", status: .pending)
                }
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(deviceText(developerMode ? "device.prep.developer.caption" : "device.prep.trust.caption"))
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 420)
            VStack(spacing: 10) {
                DevicePhonePreview(developerMode: developerMode)
                Text(deviceText("device.phone.caption")).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .frame(width: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyToInstallPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                preparationRow(number: nil, title: "device.prep.usb", status: .complete)
                DeviceRule().padding(.leading, 54)
                preparationRow(number: nil, title: "device.prep.trust.done", status: .complete)
                DeviceRule().padding(.leading, 54)
                preparationRow(number: nil, title: "device.prep.developer.done", status: .complete)
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(spacing: 0) {
                summaryRow(title: "device.team", value: MacLocalization.teamSummary(model.selectedTeam))
                DeviceRule().padding(.leading, 16)
                summaryRow(title: "device.install.version", value: projectVersion)
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(deviceText("device.d04.note"))
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 784, alignment: .leading)
    }

    private func installedPage(isUpdate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if isUpdate {
                InfoBanner(title: "device.d09.banner.title", detail: versionDifference, kind: .info)
            }
            VStack(spacing: 0) {
                summaryRow(title: "device.app.version", value: installedVersion)
                DeviceRule().padding(.leading, 16)
                summaryRow(title: "device.signature.expiry", value: expiryDateText,
                           valueColor: expiryValueColor)
                DeviceRule().padding(.leading, 16)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deviceText("device.auto-renew.title")).font(GoFlyStyle.font(13, bold: true))
                        Text(deviceText("device.auto-renew.detail")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    }
                    Spacer(minLength: 12)
                    Toggle(deviceText("device.auto-renew.title"), isOn: Binding(
                        get: { device.map(model.autoRenewEnabled(for:)) ?? model.autoRenewEnabled },
                        set: { enabled in
                            if let device { model.setAutoRenewEnabled(enabled, for: device) }
                        }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .tint(MacColorSystem.success)
                    .accessibilityIdentifier("auto-renew-signing")
                }
                .padding(.horizontal, 18).frame(minHeight: 56)
                DeviceRule().padding(.leading, 16)
                summaryRow(title: "device.vpn.title", value: vpnStatus)
                DeviceRule().padding(.leading, 16)
                summaryRow(title: "device.team", value: MacLocalization.teamIdentitySummary(model.selectedTeam))
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !isUpdate, model.signingDaysRemaining.map({ $0 < 0 }) == true {
                InfoBanner(title: "device.signature.expired.title", detail: "device.signature.expired.detail", kind: .warning)
            }
        }
        .frame(maxWidth: 784, alignment: .leading)
    }

    private var wifiUSBPage: some View {
        InfoBanner(title: "device.d12.banner.title", detail: "device.d12.banner.detail", kind: .info)
            .frame(maxWidth: 784, alignment: .leading)
    }

    private var wifiUnavailablePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            InfoBanner(title: "device.d13.banner.title", detail: nil, kind: .warning)
            VStack(spacing: 0) {
                ForEach(1...4, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("\(index)").font(GoFlyStyle.font(11, bold: true)).foregroundStyle(GoFlyStyle.muted)
                            .frame(width: 20, height: 20).background(GoFlyStyle.disabledSurface, in: Circle())
                        Text(deviceText("device.d13.step\(index)")).font(GoFlyStyle.font(13, bold: true))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    if index < 4 { DeviceRule().padding(.leading, 48) }
                }
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: 784, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            switch state {
            case .noDevice:
                DeviceActionButton(title: "device.d01.waiting", enabled: false) {}
            case .chooseDevice:
                DeviceActionButton(title: "device.d01.waiting", enabled: false) {}
            case .checking:
                DeviceActionButton(title: "device.d01.waiting", enabled: false) {}
            case .inspectRequired:
                DeviceActionButton(title: "device.rescan") { model.inspectSelected() }
            case .trustRequired, .developerModeRequired:
                DeviceActionButton(title: "device.rescan") { model.inspectSelected() }
                DeviceActionButton(title: "device.install", primary: true, enabled: false) {}
            case .readyToInstall:
                DeviceActionButton(title: "device.install", primary: true) { model.beginFirstInstall() }
            case .installed:
                DeviceActionButton(title: "device.renew", primary: true) { model.startRenew() }
            case .updateAvailable:
                DeviceActionButton(title: "device.updateRenew", primary: true) { model.startRenew() }
            case .wifiNeedsUSB:
                DeviceActionButton(title: "device.install.usbRequired", primary: true, enabled: false) {}
            case .wifiUnavailable:
                DeviceActionButton(title: "device.rescan") { model.refreshDevices() }
                DeviceActionButton(title: "device.renew", primary: true, enabled: false) {}
            case .restartRequired:
                DeviceActionButton(title: "device.d14.restart", primary: true) { model.restartInterruptedSetup() }
            }
        }
        .padding(.horizontal, 48).frame(height: 80)
        .overlay(alignment: .top) { DeviceRule() }
    }

    private var restartRequiredPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            InfoBanner(title: restartBannerTitle, detail: restartBannerDetail, kind: .error)
            VStack(spacing: 0) {
                restartStageRow("setup.progress.build", rank: 1)
                DeviceRule().padding(.leading, 52)
                restartStageRow("setup.progress.sign", rank: 2)
                DeviceRule().padding(.leading, 52)
                restartStageRow("setup.progress.install", rank: 3)
                DeviceRule().padding(.leading, 52)
                restartStageRow("device.d14.support", rank: 4)
                DeviceRule().padding(.leading, 52)
                restartStageRow("device.d14.waiting", rank: 5)
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: 784, alignment: .leading)
    }

    private func restartStageRow(_ title: String, rank: Int) -> some View {
        let current = model.setup?.snapshot?.stage ?? .preflight
        let currentRank: Int = switch current {
        case .preflight: 0
        case .artifact: 1
        case .pairing: 2
        case .install: 3
        case .support: 4
        case .handoff: 5
        case .complete: 6
        }
        let complete = currentRank > rank
        let active = currentRank == rank
        return HStack(spacing: 14) {
            if complete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MacColorSystem.success)
                    .frame(width: 22, height: 22)
            } else if active {
                Image(systemName: "xmark.circle.fill").foregroundStyle(MacColorSystem.error)
                    .frame(width: 22, height: 22)
            } else {
                Circle().fill(MacColorSystem.progressPendingIndicator).frame(width: 22, height: 22)
            }
            Text(deviceText(title)).font(GoFlyStyle.font(13))
            Spacer(minLength: 0)
            Text(deviceText(complete ? "device.d14.stage.done" : active ? "device.d14.stage.interrupted" : "device.d14.stage.pending"))
                .font(GoFlyStyle.font(11))
                .foregroundStyle(active ? MacColorSystem.annotation : GoFlyStyle.muted)
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    private var restartBannerTitle: String {
        if isWiFiRenewFailure {
            return "device.d14.banner.title"
        }
        return "device.d14.generic.title"
    }

    private var restartBannerDetail: String {
        if isWiFiRenewFailure {
            return "device.d14.banner.detail"
        }
        return "device.d14.generic.detail"
    }

    private var isWiFiRenewFailure: Bool {
        guard model.setup?.mode == .renew else { return false }
        if model.setup?.pendingTransaction?.transport == .wifi { return true }
        return ["wifi-device-not-found", "wifi-pairing-unknown", "wifi-support-unavailable",
                "wifi-renew-unknown"].contains(model.setup?.snapshot?.errorCode ?? "")
    }

    private var failureMessage: String {
        guard let failure = model.failure else { return deviceText("device.inspect.body") }
        switch failure {
        case .service("trust-required"), .service("usb-lockdown-failed"):
            return deviceText("device.d02.title")
        case .service("developer-mode-required"):
            return deviceText("device.d03.title")
        case .service("device-disconnected"), .service("usb-device-not-found"):
            return deviceText("device.connection.lost")
        default:
            return deviceText("device.inspect.body")
        }
    }

    private func deviceSubtitle(_ key: String) -> String {
        let fallback = device?.displayName ?? deviceText("device.name.fallback")
        let name = MacLocalization.deviceModelName(model.inspection?.device.modelName ?? device?.modelName,
                                                   fallback: fallback)
        let version = device?.osVersion.map { "iOS \($0)" } ?? deviceText("device.ios.pending")
        let transport = device?.transport == .wifi ? deviceText("device.connection.wifi") : deviceText("device.connection.usb")
        if key == "device.d13.subtitle" {
            let expiry = model.signingDaysRemaining.map { String(format: deviceText("device.signature.remaining"), $0) }
                ?? deviceText("device.expiry.unknown")
            return "\(deviceText("device.d13.lastConnection")) · \(expiry) · \(deviceText(key))"
        }
        if key == "device.d04.subtitle" || key == "device.d02.subtitle" || key == "device.d03.subtitle" ||
            key == "device.d08.subtitle" || key == "device.d09.subtitle" || key == "device.d12.subtitle" {
            return "\(name) · \(version) · \(transport)"
        }
        return deviceText(key)
    }

    private var projectVersion: String {
        MacLocalization.projectVersion(version: model.environment?.projectVersion,
                                       build: model.environment?.projectBuild)
    }

    private var installedVersion: String {
        guard let version = model.inspection?.appVersion else { return deviceText("device.version.pending") }
        let normalizedVersion = version.hasSuffix(".0") ? String(version.dropLast(2)) : version
        let build = model.inspection?.appBuild.map { "（build \($0)）" } ?? ""
        let latest = model.projectIsNewer ? "" : " · \(deviceText("device.version.latest"))"
        return "\(normalizedVersion)\(build)\(latest)"
    }

    private var versionDifference: String {
        let oldBuild = model.inspection?.appBuild ?? "—"
        let newBuild = model.environment?.projectBuild ?? "—"
        return String(format: deviceText("device.d09.banner.detail"), oldBuild, newBuild)
    }

    private var expiryDateText: String {
        guard let raw = model.signingExpiryISO, let date = ISO8601DateFormatter().date(from: raw) else {
            return deviceText("device.expiry.unknown")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        let days = model.signingDaysRemaining.map { String(format: deviceText("device.signature.remaining"), $0) }
            ?? deviceText("device.expiry.unknown")
        return "\(formatter.string(from: date)) · \(days)"
    }

    private var expiryValueColor: Color {
        guard let days = model.signingDaysRemaining else { return GoFlyStyle.muted }
        if days < 0 { return MacColorSystem.error }
        if days < 4 { return MacColorSystem.annotation }
        return GoFlyStyle.muted
    }

    private var vpnStatus: String {
        guard let installed = model.inspection?.vpnInstalled else { return deviceText("device.status.pending") }
        return deviceText(installed ? "device.status.installed" : "device.status.notInstalled")
    }

    private func preparationRow(number: String?, title: String, detail: String? = nil,
                                status: PreparationStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            status.icon(number: number)
            VStack(alignment: .leading, spacing: 4) {
                Text(deviceText(title)).font(GoFlyStyle.font(13, bold: true))
                if let detail { Text(deviceText(detail)).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(title: String, value: String, valueColor: Color = GoFlyStyle.muted) -> some View {
        HStack(spacing: 16) {
            Text(deviceText(title)).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 16)
            Text(value).font(GoFlyStyle.font(12)).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 18).frame(minHeight: 50)
    }
}

private struct D01InstructionRow: View {
    let number: String
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(GoFlyStyle.font(13)).frame(width: 12, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(GoFlyStyle.font(13))
                if let detail { Text(detail).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PreparationStatus {
    case complete, current, pending

    @ViewBuilder func icon(number: String?) -> some View {
        switch self {
        case .complete:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MacColorSystem.success)
                .frame(width: 22, height: 22)
        case .current:
            Text(number ?? "").font(GoFlyStyle.font(11, bold: true))
                .foregroundStyle(MacColorSystem.primaryActionText)
                .frame(width: 22, height: 22).background(MacColorSystem.primaryActionSurface, in: Circle())
        case .pending:
            Text(number ?? "").font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.disabled)
                .frame(width: 22, height: 22).background(GoFlyStyle.disabledSurface, in: Circle())
        }
    }
}

private struct DevicePhonePreview: View {
    let developerMode: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(MacColorSystem.deviceMockFrame)
                .frame(width: 220, height: 440)
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(MacColorSystem.deviceMockScreen)
                .frame(width: 202, height: 420)
                .overlay {
                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 5) {
                            Text(deviceText(developerMode ? "device.mock.developer.title" : "device.mock.trust.title"))
                                .font(GoFlyStyle.font(9, bold: true)).foregroundStyle(MacColorSystem.primaryText)
                            Text(deviceText(developerMode ? "device.mock.developer.detail" : "device.mock.trust.detail"))
                                .font(GoFlyStyle.font(8)).foregroundStyle(MacColorSystem.secondaryText)
                                .multilineTextAlignment(.center)
                            Rectangle().fill(MacColorSystem.separator).frame(height: 0.5).padding(.top, 3)
                            Text(deviceText(developerMode ? "device.mock.developer.action" : "device.mock.trust.action"))
                                .font(GoFlyStyle.font(8, bold: true)).foregroundStyle(MacColorSystem.accent)
                                .frame(maxWidth: .infinity).frame(height: 25)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(MacColorSystem.annotation, lineWidth: 2))
                            Text(deviceText(developerMode ? "device.mock.cancel" : "device.mock.deny"))
                                .font(GoFlyStyle.font(8)).foregroundStyle(MacColorSystem.accent)
                                .frame(maxWidth: .infinity).frame(height: 20)
                        }
                        .padding(10).background(MacColorSystem.deviceMockCard, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 17)
                        .offset(y: developerMode ? -36 : -30)
                        Spacer()
                    }
                }
                .frame(width: 202, height: 420)
                .offset(x: 9, y: 10)
            Text(deviceText("device.mock.tap"))
                .font(GoFlyStyle.font(11, bold: true)).foregroundStyle(MacColorSystem.primaryActionText)
                .padding(.horizontal, 16).frame(height: 26)
                .background(MacColorSystem.annotation, in: Capsule())
                .offset(x: -54, y: developerMode ? 0 : -2)
        }
        .frame(width: 220, height: 440)
        .accessibilityLabel(deviceText(developerMode ? "device.prep.developer" : "device.prep.trust"))
    }
}

private struct MessageCard: View {
    enum Kind { case neutral, warning }
    let icon: String
    let title: String
    let kind: Kind
    var showsProgress = false

    var body: some View {
        HStack(spacing: 12) {
            if showsProgress { ProgressView().controlSize(.small) }
            else { Image(systemName: icon).foregroundStyle(kind == .warning ? MacColorSystem.warning : GoFlyStyle.muted) }
            Text(title.hasPrefix("device.") ? deviceText(title) : title).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct InfoBanner: View {
    enum Kind { case info, warning, error }
    let title: String
    let detail: String?
    let kind: Kind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .info ? "info.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(kind == .info ? MacColorSystem.info : kind == .error ? MacColorSystem.error : MacColorSystem.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(deviceText(title)).font(GoFlyStyle.font(13, bold: true))
                if let detail {
                    Text(detail.hasPrefix("device.") ? deviceText(detail) : detail)
                        .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(kind == .info ? MacColorSystem.infoSurface : kind == .error ? MacColorSystem.errorSurface : MacColorSystem.warningSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(kind == .info ? MacColorSystem.infoBorder : kind == .error ? MacColorSystem.errorBorder : MacColorSystem.warningBorder, lineWidth: 0.75)
        }
    }
}

private struct DeviceActionButton: View {
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(deviceText(title)).font(GoFlyStyle.font(12, bold: true))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16).frame(height: 36)
                .foregroundStyle(enabled ? (primary ? MacColorSystem.primaryActionText : GoFlyStyle.ink) : GoFlyStyle.disabled)
                .background(surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).goFlyRowFocus(Capsule())
    }

    private var surface: Color {
        if !enabled { return GoFlyStyle.disabledSurface }
        return primary ? MacColorSystem.primaryActionSurface : GoFlyStyle.secondarySurface
    }
}

private struct DeviceRule: View {
    var body: some View { Rectangle().fill(GoFlyStyle.line).frame(height: 0.75) }
}

private extension MacDevicePageState {
    var accessibilityKey: String {
        switch self {
        case .noDevice: "D01"
        case .chooseDevice: "choose"
        case .checking: "checking"
        case .inspectRequired: "inspect"
        case .trustRequired: "D02"
        case .developerModeRequired: "D03"
        case .readyToInstall: "D04"
        case .installed: "D08"
        case .updateAvailable: "D09"
        case .wifiNeedsUSB: "D12"
        case .wifiUnavailable: "D13"
        case .restartRequired: "D14"
        }
    }
}
