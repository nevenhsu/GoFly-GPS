import GoFlyCore
import SwiftUI

/// A data-only recovery projection. Actions use the existing controller gates.
struct GoFlyRecoveryView: View {
    @ObservedObject var recovery: ConnectionRecoveryController
    @ObservedObject var store: SessionRecoveryStore
    @ObservedObject var service: ServiceController
    var maximumHeight: CGFloat
    var onSettings: () -> Void = { }
    @State private var contentHeight: CGFloat = 160

    var hasContent: Bool {
        recovery.requiresColdConfirmation || hasSummary || recovery.noticeKey != nil || storageFailure != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let key = recovery.noticeKey {
                    connectionBanner(key)
                } else if recovery.requiresColdConfirmation {
                    connectionBanner("recovery.coldClearPending")
                }
                if let failure = storageFailure {
                    storageBanner(failure)
                }
                if hasSummary {
                    Text(goFlyString("recovery.previousTask"))
                        .goFlyFont(GoFlyFont.headline)
                        .accessibilityIdentifier("recovery.summary.title")
                    summary
                    action("recovery.discard", id: "recovery.discard") {
                        recovery.discardUnverifiedMovement()
                    }
                }
                if recovery.requiresColdConfirmation && recovery.noticeKey != nil {
                    action("onboarding.vpn.check", id: "recovery.checkConnection") { recovery.checkConnection() }
                        .disabled(!recovery.canCheck)
                }
                if recovery.requiresColdConfirmation || recovery.noticeKey != nil {
                    action("operation.settings", id: "recovery.settings", perform: onSettings)
                }
                if hasContent && store.isSaving {
                    ProgressView(goFlyString("recovery.saving"))
                        .goFlyFont(GoFlyFont.footnote)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(44, maximumHeight)))
        .goFlyCard(floating: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.panel")
    }

    private func connectionBanner(_ key: String) -> some View {
        let cold = recovery.requiresColdConfirmation
        let tone: GoFlyStatusTone = key == "recovery.connectionRecovered" ? .success : .danger
        return GoFlyStatusBanner(tone: tone, title: goFlyString(key),
            message: key == "recovery.connectionRecovered" ? nil : goFlyString("recovery.connectionGuidance"),
            actionTitle: key == "recovery.connectionRecovered" ? nil : goFlyString(cold ? "toast.restore" : "common.retry"),
            onAction: {
                if cold { _ = service.restoreGPS() }
                else { recovery.checkConnection() }
            }, identifier: "recovery.connectionBanner",
            actionEnabled: cold ? service.canRestoreGPS : recovery.canCheck,
            actionIdentifier: cold ? "recovery.restoreGPS" : "recovery.checkConnection",
            titleIdentifier: "recovery.notice")
    }

    private func storageBanner(_ failure: SessionRecoveryFailure) -> some View {
        let canRetry = store.loadState == .ready && store.hasUnsavedChanges
            && [.writeFailed, .unavailable, .unsafeFile].contains(failure)
        let message = goFlyString(failure.localizationKey)
            + (store.hasUnsavedChanges ? " " + goFlyString("recovery.unsaved") : "")
        return GoFlyStatusBanner(tone: .danger, title: goFlyIssueTitle(for: failure.localizationKey), message: message,
            actionTitle: canRetry ? goFlyString("operation.retry") : nil,
            onAction: canRetry ? { _ = store.retrySaving() } : nil,
            identifier: "recovery.storageError", actionEnabled: !store.isSaving,
            actionIdentifier: "recovery.retrySaving")
    }

    private var storageFailure: SessionRecoveryFailure? {
        if case .blocked(let failure) = store.loadState { return failure }
        return store.error
    }

    private var hasSummary: Bool {
        recovery.unverifiedMovement != nil || (recovery.requiresColdConfirmation &&
            (recovery.unverifiedUncertainty.map { $0.source != .unverifiedPreviousMovement } ?? false))
    }

    @ViewBuilder private var summary: some View {
        switch recovery.unverifiedMovement {
        case .route(let route):
            Text(goFlyString("mode.route")).goFlyFont(GoFlyFont.subheadlineEmphasis)
            Text(goFlyLocalizedFormat(goFlyString("recovery.routeProgress"),
                route.progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(GoFlyPreferences.shared.locale))))
                .accessibilityIdentifier("recovery.routeProgress")
            if route.usesPositionAxis {
                HStack(alignment: .top) {
                    Text(goFlyString("route.axis.origin"))
                    Spacer(minLength: 8)
                    Text(goFlyString("route.axis.destination")).multilineTextAlignment(.trailing)
                }
                .goFlyFont(GoFlyFont.caption)
            }
            Text(goFlyString("route.direction.\(route.heading.rawValue)"))
                .accessibilityIdentifier("recovery.routeHeading")
            if route.roundTripEnabled { Text(goFlyString("route.roundTrip")) }
        case .wander(let wander):
            Text(goFlyLocalizedFormat(goFlyString("joystick.currentTarget"), wander.target.place.title))
                .accessibilityIdentifier("recovery.wanderTarget")
        case .manual:
            Text(goFlyString("recovery.manualWaiting"))
                .accessibilityIdentifier("recovery.manualSummary")
        case nil:
            Text(goFlyString("recovery.uncertain"))
                .accessibilityIdentifier("recovery.uncertainty")
            if let place = recovery.unverifiedUncertainty?.requestedPlace {
                Text(goFlyLocalizedFormat(goFlyString("operation.destination"), place.title))
                    .accessibilityIdentifier("recovery.requestedPlace")
            }
        }
    }

    private func action(_ key: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(goFlyString(key))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
        .accessibilityIdentifier(id)
    }
}
