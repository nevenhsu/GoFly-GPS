import GoFlyCore
import GoFlyTransport
import SwiftUI
#if DEBUG && targetEnvironment(simulator)
import UIKit
#endif

@main
struct GoFlyApp: App {
    @StateObject private var bootstrap: GoFlySetupBootstrap

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if let pasteboardText = GoFlyUITestOverrides.value("-gofly-ui-pasteboard") {
            UIPasteboard.general.string = pasteboardText
        }
        if !GoFlyUITestOverrides.isFrameMode {
            Diagnostics.shared.start()
            GoFlyPathMonitor.shared.start()
        }
        #else
        Diagnostics.shared.start()
        GoFlyPathMonitor.shared.start()
        #endif
        _ = GoFlyPreferences.shared
        _bootstrap = StateObject(wrappedValue: GoFlySetupBootstrap())
    }

    var body: some Scene {
        // WindowGroup may evaluate its lazy builder on SwiftUI's renderer.
        // Capture the view value; its body owns all main-actor state access.
        let content = GoFlySceneContent(bootstrap: bootstrap)
        WindowGroup { @Sendable in content }
    }
}

private struct GoFlySceneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = GoFlyPreferences.shared
    @StateObject private var systemPresentationDim = GoFlySystemPresentationDimState()
    @ObservedObject var bootstrap: GoFlySetupBootstrap
    @AppStorage("gofly.onboarding.complete") private var onboardingComplete = false
    @State private var shouldCollapseMapAfterFirstOnboarding = false
    @State private var uiTestOnboardingComplete = false

    private var shouldShowMapAfterOnboarding: Bool {
#if DEBUG && targetEnvironment(simulator)
        if GoFlyUITestOverrides.isFirstLaunchFixture { return uiTestOnboardingComplete }
#endif
        return onboardingComplete
    }

    var body: some View {
            Group {
                galleryOrStartupContent
            }
            .environmentObject(systemPresentationDim)
            .overlay {
                if systemPresentationDim.isPresented {
                    GoFlyStyle.systemPresentationDimSupplement(for: colorScheme)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .environment(\.locale, preferences.locale)
            .preferredColorScheme(preferences.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                Diagnostics.shared.record("background.scene", category: .background, level: .notice, [
                    "phase": .text(Self.label(phase)),
                    "onboarding": .flag(onboardingComplete)
                ])
                if phase == .active {
                    preferences.refreshSystemPreferences()
                    bootstrap.refreshPendingMacSetup()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                preferences.refreshSystemPreferences()
            }
    }

    /// Simulator-only component gallery, reachable only with
    /// `-gofly-ui-gallery`; every other launch path is unchanged.
    @ViewBuilder
    private var galleryOrStartupContent: some View {
        #if DEBUG && targetEnvironment(simulator)
        if let frame = GoFlyUITestOverrides.frame {
            GoFlyFigmaFrameFixture(frame: frame, runtime: bootstrap.runtime)
        } else if GoFlyUITestOverrides.contains("-gofly-ui-gallery") {
            GoFlyComponentGallery()
        } else {
            startupContent
        }
        #else
        startupContent
        #endif
    }

    @ViewBuilder
    private var startupContent: some View {
        if let runtime = bootstrap.runtime {
            normalRuntimeView(runtime)
        } else {
            switch bootstrap.phase {
            case .preparing:
                GoFlyStartupView()
            case .awaitingMacInstall, .waitingForMac:
                GoFlyMacSetupOnboardingView()
            case .awaitingPairingImport:
                GoFlyPairingImportView(onImported: bootstrap.pairingImported)
            case .ordinaryStartup, .completed:
                GoFlyStartupView()
            case .blocked:
                GoFlySetupLockView(phase: bootstrap.phase, onRetry: bootstrap.retry)
            }
        }
    }

    @ViewBuilder
    private func normalRuntimeView(_ runtime: GoFlyRuntimeAssembly) -> some View {
        Group {
            if shouldShowMapAfterOnboarding {
                GoFlyMapView(
                    service: runtime.service,
                    recoveryStore: runtime.sessionRecovery,
                    movement: runtime.movement,
                    setupMetadata: bootstrap.metadata,
                    initialSheetDetent: shouldCollapseMapAfterFirstOnboarding ? .collapsed : nil
                )
            } else {
                GoFlyOnboardingView(controller: runtime.onboarding) {
                    shouldCollapseMapAfterFirstOnboarding = true
#if DEBUG && targetEnvironment(simulator)
                    if GoFlyUITestOverrides.isFirstLaunchFixture {
                        uiTestOnboardingComplete = true
                    } else {
                        onboardingComplete = true
                    }
#else
                    onboardingComplete = true
#endif
                }
            }
        }
        .onChange(of: preferences.effectiveLanguage) { _, _ in
            runtime.movement.continuation.refreshPresentation()
        }
        .environmentObject(runtime.favorites)
        .environmentObject(runtime.importedRoutes)
        .environmentObject(runtime.favoriteRoutes)
        .task {
            await runtime.importedRoutes.load()
            await runtime.favoriteRoutes.load()
        }
    }
}

private extension GoFlySceneContent {
    static func label(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
