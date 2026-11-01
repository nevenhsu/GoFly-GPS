import AppKit
import CoreGraphics
import SwiftUI
import GoFlyMacCore

struct MacInstallScreen: View {
    @Bindable var model: MacAppModel
    @Bindable var setup: MacSetupModel
    @State private var showKeychainIllustration = false
    @State private var keychainPromptObservedAt: Date?

    var body: some View {
        HStack(spacing: 0) {
            MacDeviceSidebar(model: model)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        content
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
        .accessibilityIdentifier("install-\(screenState.rawValue)")
        .task(id: preflightKey) { await startPreflightIfNeeded() }
        .task(id: hitDeviceLimit) { if hitDeviceLimit { model.loadRegisteredDevices() } }
        .task(id: setup.autoRenewState) {
            guard setup.isAutomaticRenewal, setup.autoRenewState == .failed,
                  !setup.hasRecordedTransaction,
                  setup.pendingTransaction?.transport == .wifi,
                  case .service(let code)? = setup.failure else { return }
            model.showWifiRenewUnavailable(code)
        }
        .task(id: isWaitingForArtifact) {
            showKeychainIllustration = false
            keychainPromptObservedAt = nil
            guard isWaitingForArtifact else { return }
            while !Task.isCancelled, isWaitingForArtifact {
                if Self.visibleKeychainPrompt {
                    let observedAt = keychainPromptObservedAt ?? Date()
                    keychainPromptObservedAt = observedAt
                    if Date().timeIntervalSince(observedAt) >= 3 {
                        showKeychainIllustration = true
                        return
                    }
                } else {
                    keychainPromptObservedAt = nil
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private enum ScreenState: String {
        case preflight, ready, installing, activation, complete, incomplete
    }

    private var screenState: ScreenState {
        if setup.snapshot?.isComplete == true { return .complete }
        if setup.isBusy {
            if setup.progressStage == .handoff && setup.mode == .install { return .activation }
            if setup.progressStage == nil && setup.snapshot == nil { return .preflight }
            return .installing
        }
        if setup.failure != nil, !setup.hasRecordedTransaction { return .ready }
        if setup.snapshot?.stage == .preflight,
           setup.snapshot?.outcome == .ready,
           setup.failure == nil { return .ready }
        if setup.hasRecordedTransaction { return .incomplete }
        return .preflight
    }

    private var isWaitingForArtifact: Bool {
        setup.isBusy && setup.progressStage == .artifact
    }

    private var preflightKey: String {
        "\(setup.isRestored)-\(setup.isBusy)-\(setup.hasRecordedTransaction)-\(setup.snapshot?.stage.rawValue ?? "none")-\(setup.failure != nil)-\(model.selectedID ?? "")-\(model.selectedTeam?.teamID ?? "")"
    }

    private var selectedDevice: ConnectedDevice? { model.selected }
    private var deviceBreadcrumb: String {
        guard let selectedDevice else { return installText("device.crumb") }
        return String(format: installText("device.crumb.selected"), selectedDevice.displayName)
    }
    private var isCaptureKeychainVariant: Bool {
#if DEBUG
        CaptureLaunchOptions.screen == "D05"
#else
        false
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(deviceBreadcrumb)
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            Text(title)
                .font(GoFlyStyle.font(28, bold: true)).padding(.top, 8)
            Text(subtitle)
                .font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
        }
        .padding(.bottom, 33)
    }

    private var title: String {
        switch screenState {
        case .preflight, .ready: installText("device.d04.title")
        case .installing:
            if setup.mode == .renew {
                installText(setup.isAutomaticRenewal ? "setup.renew.auto.title" : "setup.renew.title")
            } else {
                installText("setup.install.title")
            }
        case .activation: installText("setup.activation.title")
        case .complete:
            installText(setup.mode == .renew ? "setup.renew.complete.title" : "setup.complete.title")
        case .incomplete: installText("setup.incomplete.title")
        }
    }

    private var subtitle: String {
        switch screenState {
        case .preflight, .ready:
            return deviceDescription
        case .installing:
            if setup.mode == .renew {
                return installText(setup.isAutomaticRenewal ? "setup.renew.auto.subtitle" : "setup.renew.subtitle")
            }
            return installText("setup.install.subtitle")
        case .activation:
            return installText("setup.activation.subtitle")
        case .complete:
            if setup.mode == .renew { return installText("setup.renew.complete.subtitle") }
            return installText("setup.complete.subtitle")
        case .incomplete:
            return installText("setup.incomplete.subtitle")
        }
    }

    private var deviceDescription: String {
        guard let device = selectedDevice else { return installText("setup.device.pending") }
        let transport = device.transport == .usb ? installText("setup.transport.usb") : installText("setup.transport.wifi")
        let os = device.osVersion.map { "iOS \($0)" } ?? installText("setup.os.pending")
        let name = MacLocalization.deviceModelName(model.inspection?.device.modelName ?? device.modelName,
                                                   fallback: device.displayName)
        return "\(name) · \(os) · \(transport)"
    }

    @ViewBuilder private var content: some View {
        switch screenState {
        case .preflight, .ready:
            readyContent
        case .installing:
            installingContent
        case .activation:
            activationContent
        case .complete:
            completionContent
        case .incomplete:
            incompleteContent
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                readinessRow("device.prep.usb")
                InstallRule().padding(.leading, 54)
                readinessRow("device.prep.trust.done")
                InstallRule().padding(.leading, 54)
                readinessRow("device.prep.developer.done")
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(spacing: 0) {
                valueRow(title: "setup.team", value: teamDescription)
                InstallRule().padding(.leading, 20)
                valueRow(title: "setup.version", value: projectDescription)
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(installText("device.d04.note"))
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = setup.failure {
                NoticeBanner(title: "setup.preflight.failed", detail: failureText(failure), kind: .warning)
            }
        }
    }

    private var installingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if setup.mode == .renew {
                NoticeBanner(title: setup.isAutomaticRenewal ? "setup.renew.warning.auto.title" : "setup.renew.warning.title",
                             detail: installText(setup.isAutomaticRenewal ? "setup.renew.warning.auto.detail" : "setup.renew.warning.detail"),
                             kind: .warning)
            }
            HStack(alignment: .top, spacing: 64) {
                VStack(spacing: 0) {
                    ForEach(Array(progressRows.enumerated()), id: \.offset) { index, row in
                        ProgressStageRow(title: row.title, detail: row.detail, status: row.status)
                        if index < progressRows.count - 1 { InstallRule().padding(.leading, 54) }
                    }
                }
                .frame(maxWidth: showKeychainIllustration || isCaptureKeychainVariant ? 420 : .infinity)
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if showKeychainIllustration || isCaptureKeychainVariant {
                    keychainPromptPreview
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keychainPromptPreview: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .leading) {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10).fill(MacColorSystem.mockControl)
                        .frame(width: 48, height: 48)
                    Text(installText("setup.keychain.message"))
                        .font(GoFlyStyle.font(12, bold: true)).multilineTextAlignment(.center)
                    Text(installText("setup.keychain.password"))
                        .font(GoFlyStyle.font(10)).foregroundStyle(GoFlyStyle.muted)
                        .multilineTextAlignment(.center)
                    keychainButton("setup.keychain.allowAlways", highlighted: true)
                    keychainButton("setup.keychain.deny")
                    keychainButton("setup.keychain.allow")
                }
                .padding(.vertical, 24).padding(.horizontal, 16).frame(width: 300)
                .background(MacColorSystem.mockWindow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.border, lineWidth: 0.75))
                Text(installText("device.mock.tap"))
                    .font(GoFlyStyle.font(11, bold: true)).foregroundStyle(MacColorSystem.primaryActionText)
                    .padding(.horizontal, 14).frame(height: 26)
                    .background(MacColorSystem.annotation, in: Capsule())
                    .offset(x: -74, y: 0)
            }
            Text(installText("setup.keychain.caption"))
                .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 300)
    }

    private var activationContent: some View {
        HStack(alignment: .top, spacing: 132) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 0) {
                    if model.selectedTeam?.isFreeProvisioningTeam == true {
                        instructionRow(number: "1", title: "setup.activation.trust.title",
                                      detail: "setup.activation.trust.detail")
                        InstallRule().padding(.leading, 20)
                    }
                    instructionRow(number: model.selectedTeam?.isFreeProvisioningTeam == true ? "2" : "1",
                                  title: "setup.activation.vpn.title", detail: "setup.activation.vpn.detail")
                    InstallRule().padding(.leading, 20)
                    instructionRow(number: model.selectedTeam?.isFreeProvisioningTeam == true ? "3" : "2",
                                  title: "setup.activation.open.title", detail: "setup.activation.open.detail")
                }
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(installText("setup.activation.waiting"))
                        .font(GoFlyStyle.font(13, bold: true))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).frame(width: 420, height: 50)
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(width: 420)
            ActivationPhonePreview
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ActivationPhonePreview: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(MacColorSystem.deviceMockFrame).frame(width: 220, height: 440)
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(MacColorSystem.deviceMockScreen).frame(width: 202, height: 420)
                    .overlay {
                        VStack {
                            Spacer()
                            VStack(spacing: 7) {
                                Text(installText("setup.activation.phone.title"))
                                    .font(GoFlyStyle.font(9, bold: true))
                                Text(installText("setup.activation.phone.detail"))
                                    .font(GoFlyStyle.font(8)).foregroundStyle(GoFlyStyle.muted)
                                    .multilineTextAlignment(.center)
                                InstallRule()
                                Text(installText("setup.activation.phone.cancel"))
                                    .font(GoFlyStyle.font(8)).foregroundStyle(MacColorSystem.accent)
                                    .frame(maxWidth: .infinity).frame(height: 24)
                            }
                            .padding(10).background(MacColorSystem.deviceMockCard, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 17)
                            .offset(y: -36)
                            Spacer()
                        }
                    }
            }
            Text(installText("setup.activation.phone.caption"))
                .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                .multilineTextAlignment(.center).frame(width: 260)
        }
        .frame(width: 220)
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if setup.mode == .renew {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(GoFlyStyle.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(installText("setup.renew.complete.banner.title")).font(GoFlyStyle.font(14, bold: true))
                        Text(renewalExpiryDescription).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(height: 68)
                .background(MacColorSystem.successSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.success, lineWidth: 0.75))
                VStack(spacing: 0) {
                    valueRow(title: "setup.renew.version.title", value: projectDescription)
                    InstallRule().padding(.leading, 20)
                    valueRow(title: "setup.renew.preserved.title",
                             value: installText(setup.snapshot?.isComplete == true ? "setup.complete.preserved.value" : "setup.preserved.pending"))
                    InstallRule().padding(.leading, 20)
                    valueRow(title: "setup.renew.next-check.title", value: nextRenewalDateDescription)
                }
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(GoFlyStyle.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(installText("setup.complete.row.title")).font(GoFlyStyle.font(14, bold: true))
                        Text(expiryDescription).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(height: 68)
                .background(MacColorSystem.successSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.success, lineWidth: 0.75))
                VStack(spacing: 0) {
                    valueRow(title: "setup.complete.auto.title", value: installText("setup.complete.auto.value"))
                    InstallRule().padding(.leading, 20)
                    valueRow(title: "setup.complete.renew.title", value: installText("setup.complete.renew.value"))
                    InstallRule().padding(.leading, 20)
                    valueRow(title: "setup.complete.use.title", value: installText("setup.complete.use.value"))
                }
                .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var incompleteContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticeBanner(title: "setup.incomplete.title", detail: setup.failure.map(failureText) ?? installText("setup.incomplete.subtitle"), kind: .warning)
            if let snapshot = setup.snapshot {
                Text("\(installText("setup.incomplete.progress")) \(stageTitle(snapshot.stage))")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
            }
            if hitDeviceLimit, let devices = model.registeredDevices, !devices.isEmpty {
                registeredDeviceList(devices)
            }
        }
    }

    private var hitDeviceLimit: Bool { setup.failure == .service("device-limit-reached") }

    /// Phones holding this Team's registration slots. GoFly cannot remove
    /// them; the list only shows which phones are using the slots.
    private func registeredDeviceList(_ devices: [RegisteredDevice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: installText("setup.deviceLimit.title"), devices.count))
                .font(GoFlyStyle.font(13, bold: true))
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { InstallRule().padding(.leading, 20) }
                    HStack(spacing: 16) {
                        Text(device.name.isEmpty ? installText("setup.deviceLimit.unnamed") : device.name)
                            .font(GoFlyStyle.font(13, bold: !device.name.isEmpty))
                            .foregroundStyle(device.name.isEmpty ? GoFlyStyle.muted : GoFlyStyle.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("…" + device.id.suffix(6).uppercased())
                            .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    }
                    .padding(.horizontal, 20).frame(minHeight: 44)
                }
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(installText("setup.deviceLimit.note"))
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            switch screenState {
            case .preflight:
                InstallActionButton(title: "setup.preflight.wait", enabled: false) {}
            case .ready:
                if setup.failure == nil {
                    InstallActionButton(title: "device.install", primary: true, enabled: setup.canApply) { setup.apply() }
                } else {
                    InstallActionButton(title: "setup.preflight.retry", primary: true) { Task { await retryPreflight() } }
                }
            case .installing:
                InstallActionButton(title: "setup.cancel", enabled: !setup.cancellationRequested) { setup.cancel() }
            case .activation:
                InstallActionButton(title: "device.rescan", enabled: false) {}
            case .complete:
                InstallActionButton(title: "setup.complete.action", primary: true) { model.completeFirstInstall() }
            case .incomplete:
                InstallActionButton(title: "setup.incomplete.restart", primary: true) { model.restartInterruptedSetup() }
            }
        }
        .padding(.horizontal, 48).frame(height: 80)
        .overlay(alignment: .top) { InstallRule() }
    }

    private var teamDescription: String {
        MacLocalization.teamSummary(model.selectedTeam)
    }

    private var projectDescription: String {
        MacLocalization.projectVersion(version: model.environment?.projectVersion,
                                       build: model.environment?.projectBuild)
    }

    private var expiryDescription: String {
        guard let raw = setup.snapshot?.expiresAt,
              let date = ISO8601DateFormatter().date(from: raw) else { return installText("setup.expiry.unavailable") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return String(format: installText("setup.expiry.readback"), formatter.string(from: date), days)
    }

    private var renewalExpiryDescription: String {
        guard let raw = setup.snapshot?.expiresAt,
              let date = ISO8601DateFormatter().date(from: raw) else { return installText("setup.expiry.unavailable") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        return String(format: installText("setup.renew.expiry.readback"), formatter.string(from: date), days)
    }

    private var nextRenewalDateDescription: String {
        guard let raw = setup.snapshot?.expiresAt,
              let expiry = ISO8601DateFormatter().date(from: raw) else { return installText("setup.renew.next-check.pending") }
        let date = expiry.addingTimeInterval(-MacAutoRenewPolicy.renewalThreshold)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return String(format: installText("setup.renew.next-check"), formatter.string(from: date))
    }

    private var progressRows: [(title: String, detail: String?, status: ProgressStageStatus)] {
        let stage = setup.progressStage ?? setup.snapshot?.stage ?? (setup.isBusy ? .artifact : nil)
        let keychainActive = showKeychainIllustration || isCaptureKeychainVariant
        let building = stage == .artifact && !keychainActive
        if setup.mode == .renew {
            let installActive = stage == .install
            let installComplete = stage == .pairing || stage == .support || stage == .handoff || stage == .complete
            let verifyActive = stage == .pairing || stage == .support
            let verifyComplete = stage == .handoff || stage == .complete
            let receiptActive = stage == .handoff
            let complete = stage == .complete
            return [
                ("setup.progress.build", building ? nil : installText("setup.progress.done"), building ? .current : .complete),
                ("setup.progress.sign", building ? installText("setup.progress.waiting") : installText("setup.progress.done"), building ? .pending : .complete),
                (installText("setup.progress.install.renew"), installActive ? installText("setup.progress.in-progress") : installComplete ? installText("setup.progress.done") : nil,
                 installActive ? .inProgress : installComplete ? .complete : .pending),
                (installText("setup.progress.pairing-support"), verifyActive ? installText("setup.progress.in-progress") : verifyComplete ? installText("setup.progress.done") : nil,
                 verifyActive ? .inProgress : verifyComplete ? .complete : .pending),
                (installText("setup.progress.receipt.renew"), receiptActive ? installText("setup.progress.in-progress") : complete ? installText("setup.progress.done") : nil,
                 receiptActive ? .inProgress : complete ? .complete : .pending),
            ]
        }
        let pairingDone = stage == .install || stage == .support || stage == .handoff || stage == .complete
        let installActive = stage == .install
        let pairingActive = stage == .pairing
        let supportActive = stage == .support
        let handoffActive = stage == .handoff
        let complete = stage == .complete
        return [
            ("setup.progress.build", building ? nil : installText("setup.progress.done"), building ? .current : .complete),
            ("setup.progress.sign", keychainActive ? installText("setup.progress.waitingKeychain") : installText(building ? "setup.progress.waiting" : "setup.progress.done"), keychainActive ? .current : building ? .pending : .complete),
                ("setup.progress.install", installActive ? nil : pairingDone || supportActive ? installText("setup.progress.done") : nil, installActive ? .current : pairingDone || supportActive ? .complete : .pending),
            (pairingProgressTitle, pairingActive ? nil : pairingDone ? installText("setup.progress.done") : nil, pairingActive ? .current : pairingDone ? .complete : .pending),
            ("setup.progress.support", supportActive ? nil : stage == .handoff || stage == .complete ? installText("setup.progress.done") : nil, supportActive ? .current : stage == .handoff || stage == .complete ? .complete : .pending),
            ("setup.progress.receipt", handoffActive ? nil : complete ? installText("setup.progress.done") : nil,
             handoffActive ? .current : complete ? .complete : .pending),
        ]
    }

    private var pairingProgressTitle: String {
        setup.mode == .renew && setup.pendingTransaction?.transport == .wifi
            ? "setup.progress.pairing.verify" : "setup.progress.pairing"
    }

    private func readinessRow(_ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(GoFlyStyle.success)
            Text(installText(title)).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).frame(minHeight: 50)
    }

    private func instructionRow(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(number).font(GoFlyStyle.font(13)).frame(width: 12, alignment: .leading)
                Text(installText(title)).font(GoFlyStyle.font(13, bold: true))
                Spacer(minLength: 0)
            }
            Text(installText(detail)).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                .padding(.leading, 24).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(installText(title)).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 0)
            Text(value).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                .lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20).frame(minHeight: 50)
    }

    private func keychainButton(_ title: String, highlighted: Bool = false) -> some View {
        Text(installText(title)).font(GoFlyStyle.font(10, bold: highlighted))
            .foregroundStyle(highlighted ? MacColorSystem.accentText : GoFlyStyle.ink)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(highlighted ? MacColorSystem.accent : MacColorSystem.mockContent,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(highlighted ? MacColorSystem.annotation : GoFlyStyle.border,
                                                                     lineWidth: highlighted ? 2 : 0.75))
    }

    private func retryPreflight() async {
        await setup.retryBlockedJournal()
        guard let device = selectedDevice,
              let teamID = model.selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: teamID, allowProvisioningUpdates: true) else { return }
        setup.resetSelection()
        do {
            try setup.configure(deviceID: device.id, options: options)
            setup.preflight()
        } catch {
            return
        }
    }

    private func startPreflightIfNeeded() async {
        guard setup.isRestored, !setup.isBusy, !setup.hasRecordedTransaction,
              setup.snapshot == nil, setup.failure == nil,
              let device = selectedDevice,
              let teamID = model.selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: teamID, allowProvisioningUpdates: true) else { return }
        do {
            if setup.options == nil { try setup.configure(deviceID: device.id, options: options) }
            setup.preflight()
        } catch {
            return
        }
    }

    private func failureText(_ failure: MacSetupFailure) -> String {
        switch failure {
        case .cancelled: return installText("setup.failure.cancelled")
        case .timeout: return installText("setup.failure.timeout")
        case .unavailable: return installText("setup.failure.unavailable")
        case .invalidRequest: return installText("setup.failure.invalidRequest")
        case .invalidResponse: return installText("setup.failure.invalidResponse")
        case .service(let code):
            if setup.pendingTransaction?.transport == .wifi,
               !["signing-required", "signature-invalid", "artifact-mismatch", "configuration-invalid",
                 "dependency-mismatch", "environment-not-ready"].contains(code) {
                return installText("setup.failure.wifi")
            }
            return switch code {
            case "trust-required": installText("setup.failure.trust")
            case "developer-mode-required": installText("setup.failure.developerMode")
            case "app-already-installed": installText("setup.failure.alreadyInstalled")
            case "handoff-unknown": installText("setup.failure.activation")
            case "device-disconnected": installText("setup.failure.disconnected")
            case "device-limit-reached": installText("setup.failure.deviceLimit")
            case "wifi-device-not-found", "wifi-pairing-unknown", "wifi-support-unavailable", "wifi-renew-unknown":
                installText("setup.failure.wifi")
            default: installText("setup.failure.generic")
            }
        }
    }

    private func stageTitle(_ stage: MacSetupStage) -> String {
        switch stage {
        case .preflight: installText("setup.stage.preflight")
        case .artifact: installText("setup.stage.artifact")
        case .pairing: installText("setup.stage.pairing")
        case .install: installText("setup.stage.install")
        case .support: installText("setup.stage.support")
        case .handoff: installText("setup.stage.handoff")
        case .complete: installText("setup.stage.complete")
        }
    }

    private static var visibleKeychainPrompt: Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            return owner == "SecurityAgent" &&
                (title.localizedCaseInsensitiveContains("codesign") ||
                 title.localizedCaseInsensitiveContains("Apple Development"))
        }
    }
}

private enum ProgressStageStatus { case complete, current, inProgress, pending }

private struct ProgressStageRow: View {
    let title: String
    let detail: String?
    let status: ProgressStageStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                switch status {
                case .complete:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(GoFlyStyle.success)
                case .current, .inProgress:
                    ProgressView().controlSize(.small).frame(width: 20, height: 20)
                case .pending:
                    Circle().fill(GoFlyStyle.disabledSurface).frame(width: 20, height: 20)
                }
            }
            Text(installText(title)).font(GoFlyStyle.font(13, bold: status == .current || status == .inProgress))
            Spacer(minLength: 8)
            if let detail {
                Text(installText(detail)).font(GoFlyStyle.font(11)).foregroundStyle(status == .current ? MacColorSystem.warning : GoFlyStyle.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20).frame(minHeight: 50)
    }
}

private struct NoticeBanner: View {
    enum Kind { case warning }
    let title: String
    let detail: String
    let kind: Kind

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MacColorSystem.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(installText(title)).font(GoFlyStyle.font(13, bold: true))
                Text(detail).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(MacColorSystem.warningSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MacColorSystem.warningBorder, lineWidth: 0.75))
    }
}

private struct InstallActionButton: View {
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(installText(title)).font(GoFlyStyle.font(13, bold: true)).lineLimit(1)
                .padding(.horizontal, 16).frame(height: 36)
                .foregroundStyle(enabled ? (primary ? MacColorSystem.primaryActionText : GoFlyStyle.ink) : GoFlyStyle.disabled)
                .background(enabled && primary ? MacColorSystem.primaryActionSurface : GoFlyStyle.secondarySurface, in: Capsule())
                .overlay(Capsule().strokeBorder(focused ? GoFlyStyle.ink : MacColorSystem.transparent,
                                                 lineWidth: focused ? 2 : 0))
        }
        .buttonStyle(.plain).disabled(!enabled).focused($focused)
        .opacity(enabled ? 1 : 0.6)
    }
}

private struct InstallRule: View {
    var body: some View { Rectangle().fill(GoFlyStyle.divider).frame(height: 0.75) }
}

private func installText(_ key: String) -> String { MacLocalization.text(key) }
