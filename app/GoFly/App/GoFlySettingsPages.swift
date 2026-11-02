import CoreLocation
import GoFlyCore
import Observation
import SwiftUI
import UIKit

private struct GoFlySettingsPageContainer<Content: View>: View {
    let titleKey: String
    let rootIdentifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            GoFlySheetNavBar(title: goFlyString(titleKey)) {
                GoFlyNavBackButton(title: goFlyString("settings.title"), identifier: "\(rootIdentifier).back")
            } trailing: {
                EmptyView()
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .padding(16)
            }
            .accessibilityIdentifier(rootIdentifier)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyPushedFullScreen()
    }
}

private struct GoFlySettingsSectionHeader: View {
    let titleKey: String

    var body: some View {
        Text(goFlyString(titleKey))
            .goFlyFont(GoFlyFont.caption)
            .foregroundStyle(GoFlyTextColor.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

private struct GoFlySettingsFooterNote: View {
    let textKey: String

    var body: some View {
        Text(goFlyString(textKey))
            .goFlyFont(GoFlyFont.caption)
            .foregroundStyle(GoFlyTextColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

private struct GoFlySettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(GoFlyStyle.cardSurface,
                    in: RoundedRectangle(cornerRadius: 14,
                                         style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct GoFlySettingsRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct GoFlyLocationSettingsPage: View {
    @StateObject private var status = GoFlySystemStatus()

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.location", rootIdentifier: "settings.location.page") {
            GoFlySettingsGroup {
                Button(action: status.openSystemSettings) {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.location"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.primary)
                        } value: {
                            Text(locationStatus)
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.location.status")
            }
        }
        .goFlyToastOverlay(topInset: 54) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"),
                                  identifier: "settings.location.externalOpenFailed")
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private var locationStatus: String { goFlyString(status.locationStatusKey) }
}

/// F1 → Network: Wi-Fi is a read-only status row; Local Network opens GoFly's
/// page in the Settings app, the only place iOS lets the answer be changed.
struct GoFlyNetworkSettingsPage: View {
    @StateObject private var status = GoFlySystemStatus()
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @ObservedObject private var localNetwork = GoFlyLocalNetworkAuthorization.shared

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.network", rootIdentifier: "settings.network.page") {
            GoFlySettingsGroup {
                GoFlySettingsRow {
                    GoFlySettingsValueRow {
                        Text(goFlyString("settings.wifi"))
                            .goFlyFont(GoFlyFont.body)
                            .foregroundStyle(GoFlyTextColor.primary)
                    } value: {
                        Text(goFlyString(network.isWiFiConnected ? "settings.wifi.connected" : "settings.wifi.notConnected"))
                            .goFlyFont(GoFlyFont.body)
                            .foregroundStyle(network.isWiFiConnected ? GoFlyTextColor.secondary : GoFlyTextColor.warning)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.network.wifi")

                Divider().padding(.leading, 16)

                Button(action: status.openSystemSettings) {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.localNetwork"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.primary)
                        } value: {
                            Text(localNetworkStatus)
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(localNetwork.authorization == .denied ? GoFlyTextColor.warning : GoFlyTextColor.secondary)
                        }
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.network.localNetwork")
            }
        }
        .goFlyToastOverlay(topInset: 54) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"),
                                  identifier: "settings.network.externalOpenFailed")
            }
        }
        // Returning from Settings is re-read by the shared authorization itself.
        .onAppear { localNetwork.refresh() }
    }

    private var localNetworkStatus: String {
        switch localNetwork.authorization {
        case .unknown: goFlyString("settings.status.notDetermined")
        case .granted: goFlyString("settings.localNetwork.allowed")
        case .denied: goFlyString("settings.status.denied")
        }
    }
}

struct GoFlyBackgroundSettingsPage: View {
    @ObservedObject var continuation: MovementContinuationController
    @StateObject private var status = GoFlySystemStatus()
    @State private var showingDuration = false
    private var preferences: GoFlyPreferences { GoFlyPreferences.shared }

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.backgroundTitle", rootIdentifier: "settings.background.page") {
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsGroup {
                    Button(action: status.openSystemSettings) {
                        GoFlySettingsRow {
                            GoFlySettingsValueRow {
                                Text(goFlyString("settings.background"))
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                            } value: {
                                Text(backgroundStatus)
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.secondary)
                            }
                            GoFlyIcon(GoFlySymbols.disclosure)
                                .goFlyIconSize(size: 13, maximum: 16)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.background.open")

                    Divider().padding(.leading, 16)

                    Button { showingDuration = true } label: {
                        GoFlySettingsRow {
                            GoFlySettingsValueRow {
                                Text(goFlyString("settings.background.duration"))
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                            } value: {
                                Text(GoFlyBackgroundDuration.summary(seconds: preferences.backgroundRunSeconds))
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.secondary)
                            }
                            GoFlyIcon(GoFlySymbols.disclosure)
                                .goFlyIconSize(size: 13, maximum: 16)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.background.duration")
                }

                GoFlySettingsFooterNote(textKey: "settings.background.footerNote")
            }

        }
        .sheet(isPresented: $showingDuration, onDismiss: continuation.backgroundDurationDidChange) {
            GoFlyBackgroundDurationSheet(
                seconds: preferences.backgroundRunSeconds,
                onChange: { preferences.setBackgroundRunSeconds($0) },
                onDismiss: { showingDuration = false })
        }
        .goFlyTracksSystemPresentation(showingDuration, id: "settings.background.duration")
        .goFlyToastOverlay(topInset: 54) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"),
                                  identifier: "settings.background.externalOpenFailed")
            }
            if let key = continuation.noticeKey {
                GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                                  message: goFlyString("background.systemDecidesRuntime"),
                                  identifier: "background.notice")
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private var backgroundStatus: String { goFlyString(status.backgroundStatusKey) }
}

struct GoFlyVPNSettingsPage: View {
    @ObservedObject var recovery: ConnectionRecoveryController
    @StateObject private var status = GoFlySystemStatus()
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @ObservedObject private var localNetwork = GoFlyLocalNetworkAuthorization.shared
    @State private var showingHelp = false
    @State private var issueOpenFailureKey: String?

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.vpn", rootIdentifier: "settings.vpn.page") {
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsSectionHeader(titleKey: "settings.vpn.statusSection")
                GoFlySettingsGroup {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.vpn"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.primary)
                        } value: {
                            GoFlyStatusPill(text: goFlyString(recovery.connectionState.settingsStatusKey),
                                            tone: vpnTone,
                                            action: nil,
                                            identifier: "settings.vpn.status")
                        }
                    }

                    Divider().padding(.leading, 16)

                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.vpn.lastChecked"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.primary)
                        } value: {
                            Text(goFlyString("settings.vpn.justNow"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsSectionHeader(titleKey: "settings.vpn.actionsSection")
                GoFlySettingsGroup {
                    Button(action: { GoFlyExternalLinks.openStore { _ in } }) {
                        GoFlySettingsRow {
                            GoFlySettingsValueRow {
                                Text(goFlyString("settings.vpn.downloadLocalDevVPN"))
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                            } value: {
                                Text(goFlyString("settings.vpn.appStore"))
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.secondary)
                            }
                            GoFlyIcon(GoFlySymbols.disclosure)
                                .goFlyIconSize(size: 13, maximum: 16)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.vpn.download")

                    Divider().padding(.leading, 16)

                    Button(action: status.openLocalDevVPN) {
                        GoFlySettingsRow {
                            Text(goFlyString("settings.vpn.openLocalDevVPN"))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.primary)
                            Spacer(minLength: 8)
                            GoFlyIcon(GoFlySymbols.disclosure)
                                .goFlyIconSize(size: 13, maximum: 16)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.vpn.open")
                }
            }

            Button {
                showingHelp = true
            } label: {
                // Same button as R04 (onboarding.vpn.helpLink).
                HStack(spacing: 6) {
                    GoFlyIcon(GoFlySymbols.help)
                        .goFlyIconSize(size: 20, maximum: 20)
                    Text(goFlyString("onboarding.vpn.helpLink"))
                        .goFlyFont(GoFlyFont.buttonSmall)
                }
                .foregroundStyle(GoFlyTextColor.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.vpn.help")
        }
        .navigationDestination(isPresented: $showingHelp) { GoFlyVPNHelpPage() }
        .goFlyToastOverlay(topInset: 54) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("onboarding.vpn.externalOpenFailed"),
                                  identifier: "settings.vpn.externalOpenFailed")
            }
            if recovery.connectionState != .reachable,
               let issue = ConnectionIssue.first(
                isWiFiConnected: network.isWiFiConnected,
                checkFailed: recovery.connectionState == .unavailable || recovery.connectionState == .timedOut,
                localNetworkDenied: localNetwork.authorization == .denied) {
                GoFlyConnectionIssueBanner(issue: issue, identifier: "settings.vpn.failure",
                                           onOpenFailed: { issueOpenFailureKey = $0 })
            }
            if let issueOpenFailureKey {
                GoFlyStatusBanner(tone: .danger, title: goFlyString(issueOpenFailureKey),
                                  identifier: "settings.vpn.externalOpenFailed")
            }
        }
        .onAppear {
            status.refresh()
            if recovery.canCheck { recovery.checkConnection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            issueOpenFailureKey = nil
            status.refresh()
            if recovery.canCheck { recovery.checkConnection() }
        }
    }

    private var vpnTone: GoFlyStatusTone {
        switch recovery.connectionState {
        case .reachable: .success
        case .unavailable, .timedOut: .danger
        case .checking: .warning
        case .unknown: .neutral
        }
    }
}

struct GoFlyDeviceSettingsPage: View {
    @ObservedObject var service: ServiceController
    let setupMetadata: GoFlySetupMetadata?
    @StateObject private var status = GoFlySystemStatus()
    @State private var exportItem: DiagnosticsShareItem?
    @State private var exportFailed = false

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.device", rootIdentifier: "settings.device.page") {
            let snapshot = status.deviceSnapshot(service: service, setupMetadata: setupMetadata)
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsGroup {
                    deviceField("settings.device.pairing", value: snapshot.pairingStatus, identifier: "settings.device.pairing")
                    Divider().padding(.leading, 16)
                    deviceField("settings.device.service", value: snapshot.serviceStatusDisplay, identifier: "settings.device.service")
                    Divider().padding(.leading, 16)
                    deviceField("settings.device.signingExpiry", value: snapshot.signingExpiryStatus, identifier: "settings.device.signingExpiry")
                    Divider().padding(.leading, 16)
                    deviceField("settings.device.daysLeft", value: snapshot.daysLeftStatus, identifier: "settings.device.daysLeft")
                    if GoFlyUITestOverrides.frame != "F9" {
                        Divider().padding(.leading, 16)
                        deviceField("settings.device.teamID", value: snapshot.teamIDStatus, identifier: "settings.device.teamID")
                        Divider().padding(.leading, 16)
                        deviceField("settings.device.version", value: snapshot.appVersion, identifier: "settings.device.version")
                        Divider().padding(.leading, 16)
                        deviceField("settings.device.system", value: "\(snapshot.deviceName) · \(snapshot.deviceModel) · \(snapshot.systemName) \(snapshot.systemVersion)", identifier: "settings.device.system")
                    }
                }

            }

            if GoFlyUITestOverrides.frame != "F9" {
                diagnosticsSection
            }
        }
        .sheet(item: $exportItem) { item in
            GoFlyShareSheet(url: item.url)
        }
        .goFlyTracksSystemPresentation(exportItem != nil, id: "settings.diagnostics.share")
        .goFlyToastOverlay(topInset: 54) {
            if exportFailed {
                GoFlyStatusBanner(tone: .danger,
                                  title: goFlyString("settings.diagnostics.exportFailed"),
                                  onDismiss: { exportFailed = false },
                                  identifier: "settings.diagnostics.exportFailed")
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    /// Keeps the diagnostics export reachable from Settings › Device after the
    /// UI redesign; it is the only way to collect evidence without USB.
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(goFlyString("settings.diagnostics.title"))
                .goFlyFont(GoFlyFont.headline)
            Text(goFlyString("settings.diagnostics.description"))
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GoFlySettingsAction(
                titleKey: "settings.diagnostics.export",
                action: exportDiagnostics,
                identifier: "settings.diagnostics.export"
            )
        }
        .settingsCard()
    }

    private func exportDiagnostics() {
        do {
            exportItem = DiagnosticsShareItem(url: try Diagnostics.shared.export())
            exportFailed = false
            Diagnostics.shared.record("diagnostics.export", category: .device, level: .notice, [:])
        } catch {
            exportFailed = true
            Diagnostics.shared.record("diagnostics.exportFailed", category: .device, level: .error, [:])
        }
    }

    private func deviceField(_ titleKey: String, value: String, identifier: String) -> some View {
        GoFlySettingsValueRow {
            Text(goFlyString(titleKey))
                .goFlyFont(GoFlyFont.body)
                .foregroundStyle(GoFlyTextColor.primary)
        } value: {
            Text(value)
                .goFlyFont(GoFlyFont.body)
                .foregroundStyle(GoFlyTextColor.secondary)
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct GoFlySettingsAction: View {
    let titleKey: String
    let action: () -> Void
    var identifier: String
    var disabled = false

    var body: some View {
        Button(action: action) {
            Text(goFlyString(titleKey))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

struct GoFlyHelpSettingsPage: View {
    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.help", rootIdentifier: "settings.help.page") {
            VStack(alignment: .leading, spacing: 0) {
                helpTopic("manual", symbol: GoFlySymbols.manualMovement)
                helpDivider
                helpTopic("wander", symbol: GoFlySymbols.walking)
                helpDivider
                helpTopic("arrow", symbol: GoFlySymbols.heading)
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 0) {
                helpTopic("recenter", symbol: GoFlySymbols.recenter)
                helpDivider
                helpTopic("mapPin", symbol: GoFlySymbols.place)
                helpDivider
                helpTopic("favorites", symbol: GoFlySymbols.favorite)
                helpDivider
                helpTopic("waiting", symbol: GoFlySymbols.waiting)
            }
            .settingsCard()
        }
    }

    private var helpDivider: some View {
        Divider().padding(.leading, 38).padding(.vertical, 16)
    }

    private func helpTopic(_ topic: String, symbol: GoFlyIconAsset) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GoFlyIcon(symbol)
                .goFlyIconSize(size: 20)
                .foregroundStyle(GoFlyTextColor.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(goFlyString("settings.help.\(topic)Title"))
                    .goFlyFont(GoFlyFont.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(goFlyString("settings.help.\(topic)"))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .goFlyCard()
    }
}

struct GoFlyLanguageSettingsPage: View {
    @Bindable private var preferences = GoFlyPreferences.shared

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.language", rootIdentifier: "settings.language.page") {
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsGroup {
                    ForEach(Array(GoFlyLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        Button {
                            preferences.setLanguage(language)
                        } label: {
                            GoFlySettingsRow {
                                Text(language.title)
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                                Spacer(minLength: 8)
                                if preferences.language == language {
                                    GoFlyIcon(GoFlySymbols.selected)
                                        .goFlyIconSize(size: 18)
                                        .foregroundStyle(GoFlyTextColor.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.language.\(language.rawValue)")
                    }
                }
            }
        }
    }
}

struct GoFlyAppearanceSettingsPage: View {
    @Bindable private var preferences = GoFlyPreferences.shared

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.appearance", rootIdentifier: "settings.appearance.page") {
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsGroup {
                    ForEach(Array(GoFlyAppearance.allCases.enumerated()), id: \.element.id) { index, appearance in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        Button {
                            preferences.setAppearance(appearance)
                        } label: {
                            GoFlySettingsRow {
                                Text(appearance.title)
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                                Spacer(minLength: 8)
                                if preferences.appearance == appearance {
                                    GoFlyIcon(GoFlySymbols.selected)
                                        .goFlyIconSize(size: 18)
                                        .foregroundStyle(GoFlyTextColor.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
                    }
                }
            }
        }
    }
}

struct GoFlyPreferencesSettingsPage: View {
    @Bindable private var preferences = GoFlyPreferences.shared

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.languageAndAppearance", rootIdentifier: "settings.preferences.page") {
            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsSectionHeader(titleKey: "settings.language")
                GoFlySettingsGroup {
                    ForEach(Array(GoFlyLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        Button {
                            preferences.setLanguage(language)
                        } label: {
                            GoFlySettingsRow {
                                Text(language.title)
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                                Spacer(minLength: 8)
                                if preferences.language == language {
                                    GoFlyIcon(GoFlySymbols.selected)
                                        .goFlyIconSize(size: 18)
                                        .foregroundStyle(GoFlyTextColor.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.language.\(language.rawValue)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GoFlySettingsSectionHeader(titleKey: "settings.appearance")
                GoFlySettingsGroup {
                    ForEach(Array(GoFlyAppearance.allCases.enumerated()), id: \.element.id) { index, appearance in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        Button {
                            preferences.setAppearance(appearance)
                        } label: {
                            GoFlySettingsRow {
                                Text(appearance.title)
                                    .goFlyFont(GoFlyFont.body)
                                    .foregroundStyle(GoFlyTextColor.primary)
                                Spacer(minLength: 8)
                                if preferences.appearance == appearance {
                                    GoFlyIcon(GoFlySymbols.selected)
                                        .goFlyIconSize(size: 18)
                                        .foregroundStyle(GoFlyTextColor.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
                    }
                }
            }
        }
    }
}
