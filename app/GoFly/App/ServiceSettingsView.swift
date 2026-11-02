import GoFlyCore
import Observation
import SwiftUI
import UIKit

struct ServiceSettingsView: View {
    @ObservedObject var service: ServiceController
    @ObservedObject var movement: GoFlyMovementModel
    @ObservedObject var continuation: MovementContinuationController
    @ObservedObject var recovery: ConnectionRecoveryController
    let setupMetadata: GoFlySetupMetadata?
    @StateObject private var systemStatus = GoFlySystemStatus()
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @ObservedObject private var localNetwork = GoFlyLocalNetworkAuthorization.shared
    @State private var serviceNoticeDismissed = false
    @State private var awaitingResetSuccessToast = false
    /// The ✕ hides the continuation notice until a different notice appears.
    @State private var dismissedContinuationNotice: String?
    @State private var resetSuccessToastVisible = GoFlyUITestOverrides.frame == "F1.b"

    var body: some View {
        VStack(spacing: 0) {
            GoFlySheetNavBar(title: goFlyString("settings.title")) {
                GoFlyNavBackButton(title: goFlyString("settings.backToMap"), identifier: "settings.back")
            } trailing: {
                EmptyView()
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    serviceCard
                    settingsGroups
                }
                .padding(16)
            }
        }
        .background(GoFlyStyle.canvas)
        .goFlyToastOverlay(topInset: 54) { topStatusToasts }
        .goFlyBottomToastOverlay(bottomInset: 40) { bottomStatusToasts }
        .goFlyPushedFullScreen()
        .onAppear {
            systemStatus.refresh()
            recovery.requestForegroundCheck()
        }
        .onChange(of: bannerFailure) { _, newFailure in
            if newFailure != nil { serviceNoticeDismissed = false }
        }
        .onChange(of: service.clearConfirmedAt) { _, _ in resolveResetSuccessToast() }
        .onChange(of: service.phase) { _, _ in resolveResetSuccessToast() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            systemStatus.refresh()
            recovery.requestForegroundCheck()
        }
    }

    @ViewBuilder
    private var topStatusToasts: some View {
        if let failure = bannerFailure, !serviceNoticeDismissed, failure.isConnectionFailure,
           let issue = ConnectionIssue.first(isWiFiConnected: network.isWiFiConnected, checkFailed: true,
                                             localNetworkDenied: localNetwork.authorization == .denied) {
            GoFlyConnectionIssueBanner(issue: issue, identifier: "service.error",
                                       onDismiss: { serviceNoticeDismissed = true })
        } else if bannerFailure != nil, !serviceNoticeDismissed {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString("service.stopFailed.title"),
                message: goFlyString("service.stopFailed.message"),
                actionTitle: goFlyString("operation.retry"),
                onAction: retryBannerFailure,
                onDismiss: { serviceNoticeDismissed = true },
                identifier: "service.error",
                actionEnabled: !service.nativeBusy,
                isFloating: true
            )
        }
        if let key = continuation.noticeKey, dismissedContinuationNotice != key {
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString(key),
                message: goFlyString("background.systemDecidesRuntime"),
                onDismiss: { dismissedContinuationNotice = key },
                identifier: "background.notice.compact",
                isFloating: true
            )
        }
    }

    @ViewBuilder
    private var bottomStatusToasts: some View {
        if resetSuccessToastVisible {
            GoFlyStatusBanner(
                tone: .success,
                title: goFlyString("service.resetSucceeded.title"),
                message: goFlyString("service.resetSucceeded.message"),
                onDismiss: { resetSuccessToastVisible = false },
                identifier: "service.resetSucceeded",
                isFloating: true
            )
        }
    }

    /// Settings only surfaces real connection failures; a cancelled operation is never an error here.
    private var bannerFailure: DeviceServiceFailure? {
        let failure: DeviceServiceFailure?
        if case .failed(let preparedFailure)? = service.preparedOperation?.state {
            failure = preparedFailure
        } else if service.preparedOperation == nil {
            failure = service.error
        } else {
            failure = nil
        }
        return failure == .operationCancelled ? nil : failure
    }

    private func retryBannerFailure() {
        if let operation = service.preparedOperation {
            _ = service.retryPreparedOperation(id: operation.id)
        } else {
            _ = service.start()
        }
    }

    private var settingsGroups: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("settings.permissionsAndConnection") {
                settingsLink(title: "settings.location", value: locationSummary,
                             destination: { GoFlyLocationSettingsPage() })
                settingsDivider
                settingsLink(title: "settings.network", value: networkSummary,
                             destination: { GoFlyNetworkSettingsPage() })
                settingsDivider
                settingsLink(title: "settings.vpn", value: goFlyString(recovery.connectionState.settingsStatusKey),
                             destination: { GoFlyVPNSettingsPage(recovery: recovery) })
                settingsDivider
                settingsLink(title: "settings.backgroundTitle", value: backgroundSummary, identifier: "settings.background",
                             destination: { GoFlyBackgroundSettingsPage(continuation: continuation) })
            }
            settingsSection("settings.preferences") {
                settingsLink(title: "settings.language", value: GoFlyPreferences.shared.language.title,
                             destination: { GoFlyLanguageSettingsPage() })
                settingsDivider
                settingsLink(title: "settings.appearance", value: GoFlyPreferences.shared.appearance.title,
                             destination: { GoFlyAppearanceSettingsPage() })
            }
            settingsSection("settings.deviceSection") {
                settingsLink(title: "settings.device", value: nil,
                             destination: { GoFlyDeviceSettingsPage(service: service, setupMetadata: setupMetadata) })
            }
        }
    }

    private var networkNeedsAttention: Bool { !network.isWiFiConnected || localNetwork.authorization == .denied }
    private var networkSummary: String {
        if !network.isWiFiConnected { return goFlyString("settings.wifi.notConnected") }
        if localNetwork.authorization == .denied { return goFlyString("settings.status.denied") }
        return goFlyString("settings.wifi.connected")
    }
    private var locationSummary: String { goFlyString(systemStatus.locationStatusKey) }
    private var backgroundSummary: String { goFlyString(systemStatus.backgroundStatusKey) }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ titleKey: String,
        footerKey: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goFlyString(titleKey))
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .goFlyCard(radius: 14)
            if let footerKey {
                Text(goFlyString(footerKey))
                    .goFlyFont(GoFlyFont.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func settingsLink<Destination: View>(
        title titleKey: String,
        value: String?,
        identifier: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingsRow(titleKey: titleKey, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "settings.\(titleKey.replacingOccurrences(of: "settings.", with: ""))")
    }

    private func settingsRow(titleKey: String, value: String?) -> some View {
        HStack(spacing: 12) {
            GoFlySettingsBadgeIcon(kind: settingsIconKind(for: titleKey))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            GoFlySettingsValueRow {
                Text(goFlyString(titleKey))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .multilineTextAlignment(.leading)
            } value: {
                if let value {
                    if (titleKey == "settings.location" && systemStatus.locationAuthorization == .denied) ||
                       (titleKey == "settings.network" && networkNeedsAttention) {
                        GoFlyIconLabel(title: value, icon: GoFlySymbols.warning)
                            .goFlyFont(GoFlyFont.subheadline)
                            .foregroundStyle(GoFlyTextColor.warning)
                    } else {
                        Text(value)
                            .goFlyFont(GoFlyFont.subheadline)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
            }
            GoFlyIcon(GoFlySymbols.disclosure)
                .goFlyIconSize(size: 12, maximum: 16)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func settingsIconKind(for key: String) -> GoFlySettingsIconKind {
        switch key {
        case "settings.location": .location
        case "settings.background", "settings.backgroundTitle": .background
        case "settings.vpn": .vpn
        case "settings.network": .wifi
        case "settings.language": .language
        case "settings.appearance": .appearance
        default: .device
        }
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString("service.title")).goFlyFont(GoFlyFont.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GoFlyStatusPill(text: goFlyString(statusPillTextKey), tone: statusPillTone,
                                action: nil, identifier: "service.statusPill")
                    .accessibilityValue(goFlyString(statusPillTextKey))
            }
            serviceActionButton

        }
        .padding(16)
        .goFlyCard(radius: 14)
    }

    private var statusPillTextKey: String {
        if shouldReset { return "device.status.interrupted" }
        if service.phase == .preparing { return "status.pill.connecting" }
        if movement.status == .started && service.phase != .ready { return "status.pill.stopped" }
        if GoFlyUITestOverrides.frame == "F1" { return "status.pill.started" }
        return movement.status.textKey
    }

    private var statusPillTone: GoFlyStatusTone {
        if shouldReset { return .danger }
        if service.phase == .preparing { return .warning }
        if movement.status == .started && service.phase != .ready { return GoFlySessionStatus.stopped.tone }
        if GoFlyUITestOverrides.frame == "F1" { return .success }
        return movement.status.tone
    }

    private var serviceActionButton: some View {
        let isReset = shouldReset
        let isStop = offersStop && !isReset
        return Button {
            if isReset {
                awaitingResetSuccessToast = service.forceReset()
                resetSuccessToastVisible = false
            } else if isStop {
                _ = service.stop()
            } else {
                _ = service.start()
            }
        } label: {
            HStack(spacing: 8) {
                if service.nativeBusy {
                    ProgressView()
                } else if isReset {
                    GoFlyIcon(GoFlySymbols.reset).goFlyIconSize(size: 15)
                } else if isStop {
                    GoFlyIcon(.stop).goFlyIconSize(size: 15)
                } else {
                    GoFlyIcon(GoFlySymbols.play).goFlyIconSize(size: 15)
                }
                Text(buttonTitle(isReset: isReset, isStop: isStop))
            }
        }
        .buttonStyle(GoFlyActionStyle(primary: !isReset))
        .disabled(actionDisabled(isReset: isReset, isStop: isStop))
        .accessibilityHint(isReset ? goFlyString("service.resetHint") : "")
        .accessibilityIdentifier(isReset ? "service.reset" : "service.primary")
    }

    private var shouldReset: Bool {
        service.phase == .repairRequired || service.canForceReset || GoFlyUITestOverrides.frame == "F1.a"
    }

    /// Prepared but not moving: the button reports readiness; Stop appears once a task runs.
    private var isIdleReady: Bool { service.phase == .ready && !service.hasSimulated }

    private func buttonTitle(isReset: Bool, isStop: Bool) -> String {
        if isReset { return goFlyString("service.reset") }
        if service.phase == .preparing { return goFlyString("service.connecting") }
        if isIdleReady { return goFlyString("service.readyButton") }
        if isStop { return goFlyString("service.stop") }
        return goFlyString("service.start")
    }

    private func actionDisabled(isReset: Bool, isStop: Bool) -> Bool {
        if isReset { return service.nativeBusy }
        if isStop { return !service.canStop }
        return !service.canStart
    }

    private func resolveResetSuccessToast() {
        guard awaitingResetSuccessToast, !service.nativeBusy, service.phase == .stopped else { return }
        awaitingResetSuccessToast = false
        resetSuccessToastVisible = service.clearConfirmedAt != nil
    }

    private var status: some View {
        Text(goFlyString(service.statusKey))
            .goFlyFont(GoFlyFont.subheadline)
            .foregroundStyle(GoFlyTextColor.secondary)
            .accessibilityIdentifier("service.status")
    }

    private var offersStop: Bool {
        movement.status == .simulating || movement.status == .paused
            || service.phase == .preparing || service.phase == .repairRequired || service.isRecoveringConnection
            || GoFlyUITestOverrides.frame == "F1"
    }
}
