#if DEBUG && targetEnvironment(simulator)
import GoFlyCore
import SwiftUI

/// Routes a Figma frame launch argument to an explicit, deterministic UI state.
/// Unsupported frames are listed in the screenshot manifest instead of being
/// represented by a misleading placeholder screen.
struct GoFlyFigmaFrameFixture: View {
    let frame: String
    let runtime: GoFlyRuntimeAssembly?

    @StateObject private var onboarding: OnboardingController
    @State private var didCompleteOnboarding = false
    @State private var completionRuntime: GoFlyRuntimeAssembly?

    init(frame: String, runtime: GoFlyRuntimeAssembly?) {
        self.frame = frame
        self.runtime = runtime
        _onboarding = StateObject(wrappedValue: GoFlyUITestOverrides.onboardingController(for: frame))
    }

    var body: some View {
        Group {
            if frame == "R04", didCompleteOnboarding,
               let mapRuntime = runtime ?? completionRuntime {
                mapFrame(mapRuntime, frame: "B1")
            } else {
                frameContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("figma.fixture.\(visibleFrame)")
    }

    private var visibleFrame: String {
        frame == "R04" && didCompleteOnboarding ? "B1" : frame
    }

    @ViewBuilder
    private var frameContent: some View {
        switch frame {
        case "R01":
            GoFlyStartupView()
        case "R02", "R03", "R03.a", "R04", "R04.a", "R05":
            onboardingFrame
        case "R07":
            GoFlyMacSetupOnboardingView()
        case "R08":
            GoFlySetupLockView(phase: .blocked(.identityMismatch), onRetry: {})
        case "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11",
             "C1", "C2", "C3", "C4",
             "D1", "D2", "D2.a", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D10.a",
             "D11", "D12", "D13", "D14", "D15", "D16", "D17", "D18", "D19", "D20",
             "D21", "D22", "D23",
             "E1", "E1.a", "E2", "E2.a", "E3", "E4", "E5",
             "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9":
            if let runtime {
                mapFrame(runtime, frame: frame)
            } else {
                unavailableFrame
            }
        default:
            unavailableFrame
        }
    }

    private var onboardingFrame: some View {
        GoFlyOnboardingView(controller: onboarding) {
            guard frame == "R04" else { return }
            if runtime == nil, completionRuntime == nil {
                completionRuntime = GoFlyRuntimeAssembly()
            }
            didCompleteOnboarding = true
        }
        .task {
            guard onboarding.step == .welcome else { return }
            onboarding.advanceWelcome()
            if ["R03.a", "R04", "R04.a", "R05"].contains(frame) {
                onboarding.skipLocation()
            }
            if ["R04", "R04.a", "R05"].contains(frame) {
                await onboarding.allowLocalNetwork()
            }
        }
    }

    private func mapFrame(_ runtime: GoFlyRuntimeAssembly, frame: String) -> some View {
        GoFlyMapView(
            service: runtime.service,
            recoveryStore: runtime.sessionRecovery,
            movement: runtime.movement,
            setupMetadata: nil,
            uiTestFixtureFrame: frame
        )
        .environmentObject(runtime.favorites)
        .environmentObject(runtime.importedRoutes)
        .environmentObject(runtime.favoriteRoutes)
        .task {
            await runtime.prepareUITestData()
            await runtime.importedRoutes.load()
            await runtime.favoriteRoutes.load()
            if frame == "F1" {
                _ = runtime.service.start()
                for _ in 0..<250 {
                    if runtime.service.phase == .ready && !runtime.service.nativeBusy { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            } else if frame == "F1.a" {
                await prepareStopFailureState(runtime.service)
            }
        }
    }

    private func prepareStopFailureState(_ service: ServiceController) async {
        guard service.start() else { return }
        for _ in 0..<250 {
            if service.phase == .ready && !service.nativeBusy { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard service.phase == .ready, service.stop() else { return }
        for _ in 0..<250 {
            if !service.nativeBusy { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private var unavailableFrame: some View {
        VStack(spacing: 8) {
            Text("Figma frame \(frame)")
                .goFlyFont(GoFlyFont.headline)
                .foregroundStyle(GoFlyTextColor.primary)
            Text("This frame does not have a deterministic simulator fixture yet.")
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoFlyStyle.canvas)
    }
}
#endif
