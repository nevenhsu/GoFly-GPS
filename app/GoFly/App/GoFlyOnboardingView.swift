import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    let onComplete: @MainActor () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsOpenFailed = false

    private enum Page: Hashable { case location, localNetwork, vpn }

    var body: some View {
        NavigationStack(path: navigationPath) {
            welcome
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .location:
                        location
                    case .localNetwork:
                        GoFlyLocalNetworkOnboardingView(controller: controller)
                    case .vpn:
                        GoFlyVPNOnboardingView(controller: controller, onComplete: onComplete)
                    }
                }
        }
        .tint(GoFlyStyle.primary)
    }

    private var pages: [Page] {
        switch controller.step {
        case .welcome: []
        case .location: [.location]
        case .localNetwork: [.location, .localNetwork]
        case .vpn, .complete: [.location, .localNetwork, .vpn]
        }
    }

    private var navigationPath: Binding<[Page]> {
        Binding(
            get: { pages },
            set: { newPages in
                let stepsBack = max(0, pages.count - newPages.count)
                for _ in 0..<stepsBack { controller.goBack() }
            }
        )
    }

    private var welcome: some View {
        GoFlyWelcomeView(isPreparing: false, onNext: controller.advanceWelcome)
    }

    private var location: some View {
        ScrollView {
            VStack(spacing: 16) {
                GoFlyOnboardingEmblem(symbol: .nav)
                    .padding(.top, 136)
                    .padding(.bottom, 23)
                VStack(spacing: 15) {
                    Text(goFlyString(controller.locationAuthorization == .authorized
                        ? "onboarding.location.title.authorized" : "onboarding.location.title"))
                        .goFlyFont(GoFlyFont.display)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 39)
                        .accessibilityIdentifier("onboarding.location.title")
                    Text(goFlyString("onboarding.location.message"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 287)
                        .accessibilityIdentifier("onboarding.location")
                }
                .padding(.top, 4)
                locationStatus
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas)
        .goFlyToastOverlay(topInset: 64) { locationNotices }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    switch controller.locationAuthorization {
                    case .notDetermined: Task { await controller.allowLocation() }
                    case .authorized: controller.skipLocation()
                    case .denied: openLocationSettings()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if controller.isRequestingLocation { ProgressView() }
                        Text(goFlyString(locationActionKey))
                    }
                }
                .buttonStyle(GoFlyButtonStyle(variant: .primary))
                .disabled(controller.isRequestingLocation)
                .accessibilityIdentifier("onboarding.location.allow")

                if controller.locationAuthorization != .authorized {
                    Button {
                        controller.skipLocation()
                    } label: {
                        Text(goFlyString(controller.locationAuthorization == .denied
                            ? "onboarding.location.continue" : "onboarding.location.skip"))
                    }
                    .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                    .accessibilityIdentifier("onboarding.location.skip")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 0)
            .background(GoFlyStyle.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { GoFlyThemeColor.lineSeparator.frame(height: 0.5) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refreshLocationAuthorization() }
        }
    }

    private var locationActionKey: String {
        switch controller.locationAuthorization {
        case .notDetermined: "onboarding.location.allow"
        case .authorized: "onboarding.next"
        case .denied: "onboarding.location.openSettings"
        }
    }

    @ViewBuilder private var locationStatus: some View {
        switch controller.locationAuthorization {
        case .notDetermined:
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.notDetermined")),
                            tone: .neutral, identifier: "onboarding.location.status")
                .padding(.top, 9)
        case .authorized:
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.authorized")),
                            tone: .success, identifier: "onboarding.location.status")
                .padding(.top, 9)
        case .denied:
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.denied")),
                            tone: .warning, identifier: "onboarding.location.status")
                .padding(.top, 9)
        }

    }

    @ViewBuilder private var locationNotices: some View {
        if controller.locationAuthorization == .denied {
            GoFlyStatusBanner(tone: .warning,
                              title: goFlyString("onboarding.location.deniedTitle"),
                              message: goFlyString("onboarding.location.denied"),
                              identifier: "onboarding.location.deniedBanner")
        }
        if settingsOpenFailed {
            GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"))
        }
    }

    private func openLocationSettings() {
        settingsOpenFailed = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsOpenFailed = true
            return
        }
        UIApplication.shared.open(url) { accepted in
            settingsOpenFailed = !accepted
        }
    }

}

/// Shared by bootstrap and the admitted onboarding flow so first launch opens
/// directly on the welcome page without constructing normal runtime owners early.
struct GoFlyWelcomeView: View {
    let isPreparing: Bool
    let onNext: @MainActor () -> Void

    var body: some View {
        // LocalDevVPN setup belongs to the VPN page, so Welcome carries no body copy.
        GoFlyOnboardingPage(title: "onboarding.welcome.title", symbol: .nav) {
            EmptyView()
        } actions: {
            if isPreparing {
                ProgressView(goFlyString("setup.preparing.message"))
                    .goFlyFont(GoFlyFont.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .accessibilityIdentifier("onboarding.welcome.loading")
            }
            Button {
                guard !isPreparing else { return }
                onNext()
            } label: {
                Text(goFlyString("onboarding.next"))
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .disabled(isPreparing)
            .accessibilityIdentifier("onboarding.welcome.next")
        }
    }
}

private struct GoFlyOnboardingPage<Content: View, Actions: View>: View {
    let title: String
    let symbol: GoFlyIconAsset
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isWelcome: Bool {
        title == "onboarding.welcome.title"
    }

    private var emblemTopSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 48 : 80
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoFlyOnboardingEmblem(symbol: symbol)
                    .padding(.top, emblemTopSpacing)
                Text(goFlyString(title))
                    .goFlyFont(GoFlyFont.display)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                content()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas)
        // Keep the initial welcome page visually quiet.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) { actions() }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .background(GoFlyStyle.canvas.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { GoFlyThemeColor.lineSeparator.frame(height: 0.5) }
        }
    }
}

/// A static, decorative emblem keeps first launch calm and respects Reduce Motion.
struct GoFlyOnboardingEmblem: View {
    let symbol: GoFlyIconAsset
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GoFlyIcon(symbol)
            .goFlyIconSize(size: 48, maximum: 60)
            .foregroundStyle(GoFlyTextColor.primary)
            .frame(width: 120, height: 120)
            .background(GoFlyStyle.onboardingHeroSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct GoFlyOnboardingFeatureIcon: View {
    let symbol: GoFlyIconAsset
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GoFlyIcon(symbol)
            .goFlyIconSize(size: 32, maximum: 40)
            .foregroundStyle(GoFlyTextColor.primary)
            .frame(width: 72, height: 72)
            .background(GoFlyStyle.onboardingHeroSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// R03.a: one primary button, no skip. A denied answer cannot be re-asked by
/// iOS, so the next press opens GoFly's page in Settings instead.
private struct GoFlyLocalNetworkOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsOpenFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GoFlyOnboardingEmblem(symbol: .wifi)
                    .padding(.top, 136)
                    .padding(.bottom, 23)
                VStack(spacing: 15) {
                    Text(goFlyString("onboarding.localNetwork.title"))
                        .goFlyFont(GoFlyFont.display)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 39)
                        .accessibilityIdentifier("onboarding.localNetwork.title")
                    Text(goFlyString("onboarding.localNetwork.message"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 287)
                        .accessibilityIdentifier("onboarding.localNetwork")
                }
                .padding(.top, 4)
                GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                    goFlyString(statusKey)),
                                tone: tone, identifier: "onboarding.localNetwork.status")
                    .padding(.top, 9)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas)
        .goFlyToastOverlay(topInset: 64) {
            if settingsOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Task { await allow() }
            } label: {
                HStack(spacing: 8) {
                    if controller.isRequestingLocalNetwork { ProgressView() }
                    Text(goFlyString("onboarding.localNetwork.allow"))
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .disabled(controller.isRequestingLocalNetwork)
            .accessibilityIdentifier("onboarding.localNetwork.allow")
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(GoFlyStyle.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { GoFlyThemeColor.lineSeparator.frame(height: 0.5) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller.refreshLocalNetworkAuthorization() } }
        }
    }

    private var statusKey: String {
        switch controller.localNetworkAuthorization {
        case .unknown: "onboarding.localNetwork.status.unknown"
        case .granted: "onboarding.localNetwork.status.granted"
        case .denied: "onboarding.localNetwork.status.denied"
        }
    }

    private var tone: GoFlyStatusTone {
        switch controller.localNetworkAuthorization {
        case .unknown: .neutral
        case .granted: .success
        case .denied: .warning
        }
    }

    private func allow() async {
        settingsOpenFailed = false
        // Already refused: iOS will not prompt again, so go straight to Settings.
        if controller.localNetworkAuthorization == .denied {
            openSettings()
            return
        }
        // Any answer other than granted (refused, or no answer) sends the user to Settings.
        if await controller.allowLocalNetwork() != .granted { openSettings() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsOpenFailed = true
            return
        }
        UIApplication.shared.open(url) { settingsOpenFailed = !$0 }
    }
}

private struct GoFlyVPNOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    let onComplete: @MainActor () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var showingHelp = false
    @State private var externalOpenFailed = false
    @State private var externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @ObservedObject private var localNetwork = GoFlyLocalNetworkAuthorization.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(goFlyString("onboarding.vpn.title"))
                    .goFlyFont(GoFlyFont.display)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 40)
                    .accessibilityIdentifier("onboarding.vpn.title")

                Text(goFlyString("onboarding.vpn.stepsTitle"))
                    .goFlyFont(GoFlyFont.footnoteEmphasis)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    GoFlyVPNInstructionRow(number: 1, titleKey: "onboarding.vpn.step1",
                                           accessibilityID: "onboarding.vpn.step1")
                    instructionSeparator
                    GoFlyVPNInstructionRow(number: 2, titleKey: "onboarding.vpn.stepLocalNetwork",
                                           trailingText: localNetworkStatusText,
                                           trailingIsWarning: localNetwork.authorization == .denied,
                                           accessibilityID: "onboarding.vpn.stepLocalNetwork",
                                           action: openAppSettings)
                    instructionSeparator
                    GoFlyVPNInstructionRow(number: 3, titleKey: "onboarding.vpn.step2",
                                           showsChevron: true, accessibilityID: "onboarding.vpn.step2",
                                           action: openLocalDevVPN)
                    instructionSeparator
                    GoFlyVPNInstructionRow(number: 4, titleKey: "onboarding.vpn.step3",
                                           accessibilityID: "onboarding.vpn.step3")
                    instructionSeparator
                    GoFlyVPNInstructionRow(number: 5, titleKey: "onboarding.vpn.step4",
                                           accessibilityID: "onboarding.vpn.step4",
                                           action: controller.checkConnection)
                }
                .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 12)

                Button { showingHelp = true } label: {
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
                .accessibilityIdentifier("onboarding.vpn.help.open")
                .padding(.bottom, 20)

                vpnStatus
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas)
        .goFlyToastOverlay(topInset: 64) { vpnToasts }
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                if controller.vpnState == .reachable {
                    controller.advanceVPN(onAdvance: onComplete)
                } else {
                    controller.checkConnection()
                }
            } label: {
                HStack(spacing: 8) {
                    if controller.isChecking || controller.isAdvancing { ProgressView() }
                    Text(goFlyString(checkButtonKey))
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .disabled(controller.isChecking || controller.isAdvancing)
            .accessibilityIdentifier("onboarding.vpn.check")
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(GoFlyStyle.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { GoFlyThemeColor.lineSeparator.frame(height: 0.5) }
        }
        .onAppear {
            isVisible = true
#if DEBUG && targetEnvironment(simulator)
            let connectedFixture = GoFlyUITestOverrides.frame == "R04"
                && GoFlyUITestOverrides.contains("-gofly-ui-vpn-reachable")
            let shouldCheckImmediately = !["R04", "R05"].contains(GoFlyUITestOverrides.frame ?? "")
                || connectedFixture
            controller.setVPNActive(shouldCheckImmediately && scenePhase == .active)
#else
            controller.setVPNActive(scenePhase == .active)
#endif
        }
        .onDisappear {
            isVisible = false
            controller.setVPNActive(false)
        }
        .onChange(of: scenePhase) { _, phase in
#if DEBUG && targetEnvironment(simulator)
            let keepsVPNFrameStatic = GoFlyUITestOverrides.frame == "R04"
                && GoFlyUITestOverrides.contains("-gofly-ui-vpn-static")
            controller.setVPNActive(isVisible && phase == .active && !keepsVPNFrameStatic)
#else
            controller.setVPNActive(isVisible && phase == .active)
#endif
        }
        .onChange(of: controller.vpnState) { _, state in
            guard state == .reachable else { return }
            controller.advanceVPN(onAdvance: onComplete)
        }
        .navigationDestination(isPresented: $showingHelp) {
            GoFlyVPNHelpPage(onReturn: recheckAfterHelp)
        }
    }

    private var instructionSeparator: some View {
        GoFlyThemeColor.lineSeparator
            .frame(height: 0.5)
            .padding(.leading, 54)
            .padding(.trailing, 16)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var vpnStatus: some View {
        switch controller.vpnState {
        case .reachable:
            EmptyView()
        case .checking:
            GoFlyStatusPill(text: goFlyString("onboarding.vpn.checking"), tone: .warning,
                            identifier: "onboarding.vpn.status")
        case .unavailable, .timedOut:
            GoFlyStatusPill(text: goFlyString("onboarding.vpn.help.notReachable"), tone: .danger,
                            identifier: "onboarding.vpn.status")
        case .unknown:
            GoFlyStatusPill(text: goFlyString("onboarding.vpn.help.notChecked"), tone: .neutral,
                            identifier: "onboarding.vpn.status")
        }
    }

    /// R04.a: the first `ConnectionIssue` that applies, shared with the map and settings.
    @ViewBuilder private var vpnToasts: some View {
        if controller.vpnState != .reachable,
           let issue = ConnectionIssue.first(
            isWiFiConnected: network.isWiFiConnected,
            checkFailed: controller.vpnState == .unavailable || controller.vpnState == .timedOut,
            localNetworkDenied: localNetwork.authorization == .denied) {
            GoFlyConnectionIssueBanner(issue: issue, identifier: "onboarding.vpn.failure",
                                       detail: issue == .vpnNotConnected ? controller.vpnFailureDetail : nil,
                                       onOpenFailed: { key in
                                           externalOpenFailureKey = key
                                           externalOpenFailed = true
                                       })
                .id(controller.vpnFailureRevision)
        }
        if externalOpenFailed {
            GoFlyStatusBanner(tone: .danger, title: goFlyString(externalOpenFailureKey),
                              identifier: "onboarding.vpn.externalOpenFailed")
        }
    }

    private var checkButtonKey: String {
        switch controller.vpnState {
        case .reachable, .checking: "onboarding.vpn.checking"
        case .unavailable, .timedOut, .unknown: "onboarding.vpn.check"
        }
    }

    private func openLocalDevVPN() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        GoFlyExternalLinks.openLocalDevVPN { externalOpenFailed = !$0 }
    }

    private var localNetworkStatusText: String {
        switch localNetwork.authorization {
        case .unknown: goFlyString("onboarding.localNetwork.status.unknown")
        case .granted: goFlyString("onboarding.localNetwork.status.granted")
        case .denied: goFlyString("onboarding.localNetwork.status.denied")
        }
    }

    private func openAppSettings() {
        externalOpenFailed = false
        externalOpenFailureKey = "settings.externalOpenFailed"
        GoFlyExternalLinks.openAppSettings { externalOpenFailed = !$0 }
    }

    private func recheckAfterHelp() {
        guard scenePhase == .active else { return }
        controller.setVPNActive(true)
    }
}
