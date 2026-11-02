import GoFlyCore
import SwiftUI

/// The same preparation presentation is used by map Go and service Start.
struct GoFlyOperationPanel: View {
    var operation: PreparedOperationSnapshot?
    var unconfirmedFailure: DeviceServiceFailure?
    var nativeBusy: Bool
    var maximumHeight: CGFloat
    var reasonIdentifier: String
    var cancelIdentifier = "operation.cancel"
    var onCancel: (UUID) -> Void
    var onRetry: (UUID) -> Void
    var onSettings: (() -> Void)?
    var onReturn: () -> Void
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let operation {
                    preparedContent(operation)
                } else if let failure = unconfirmedFailure, failure.isConnectionFailure {
                    connectionLostContent(message: goFlyString("teleport.positionUnconfirmed"))
                    Button(goFlyString("operation.return"), action: onReturn)
                        .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                        .accessibilityIdentifier("operation.return")
                } else if let failure = unconfirmedFailure {
                    GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue),
                        message: goFlyString("teleport.positionUnconfirmed") + " " + goFlyString("operation.failureGuidance"),
                        actionTitle: onSettings == nil ? nil : goFlyString("operation.settings"),
                        onAction: onSettings, identifier: "operation.unconfirmed",
                        actionIdentifier: "operation.settings", titleIdentifier: reasonIdentifier)
                    Button(goFlyString("operation.return"), action: onReturn)
                        .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                        .accessibilityIdentifier("operation.return")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(100, maximumHeight)))
        .goFlyCard(floating: true)
        .accessibilityIdentifier("operation.panel")
    }

    @ViewBuilder private func preparedContent(_ operation: PreparedOperationSnapshot) -> some View {
        switch operation.state {
        case .preparing:
            HStack(alignment: .top, spacing: 8) {
                ProgressView().accessibilityHidden(true)
                Text(goFlyString(operation.attempt.value == 1 ? preparationTitle(operation.source) : "operation.retrying"))
                    .goFlyFont(GoFlyFont.headline)
            }
            Text(goFlyLocalizedFormat(goFlyString("operation.attempt"), operation.attempt.value))
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityIdentifier("operation.attempt")
            sourceSummary(operation.source)
            Button(goFlyString("operation.cancel")) { onCancel(operation.id) }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .accessibilityIdentifier("operation.cancel")
        case .failed(let failure) where failure.isConnectionFailure:
            connectionLostContent(message: goFlyString("operation.failureGuidance"))
            Button(goFlyString("operation.retry")) { onRetry(operation.id) }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .disabled(nativeBusy)
                .accessibilityIdentifier("operation.retry")
            sourceSummary(operation.source)
            Button(goFlyString("operation.cancel")) { onCancel(operation.id) }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .disabled(nativeBusy)
                .accessibilityIdentifier(cancelIdentifier)
        case .failed(let failure):
            GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue),
                message: goFlyString("operation.failureGuidance"),
                actionTitle: goFlyString("operation.retry"), onAction: { onRetry(operation.id) },
                identifier: "operation.failure", actionEnabled: !nativeBusy,
                actionIdentifier: "operation.retry", titleIdentifier: reasonIdentifier)
            sourceSummary(operation.source)
            Button(goFlyString("operation.cancel")) { onCancel(operation.id) }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .disabled(nativeBusy)
                .accessibilityIdentifier(cancelIdentifier)
        case .cancelled:
            ProgressView(goFlyString("operation.cancelling")).goFlyFont(GoFlyFont.headline)
            Text(goFlyString("operation.waitForReturn"))
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
            Button(goFlyString("operation.cancel")) { }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .disabled(true)
                .accessibilityIdentifier("operation.cancel")
        }
    }

    /// A lost connection is explained by the one connection toast; the panel only says what
    /// happened to this operation, without a second error banner.
    @ViewBuilder private func connectionLostContent(message: String) -> some View {
        Text(goFlyString("recovery.connectionLost"))
            .goFlyFont(GoFlyFont.headline)
            .accessibilityIdentifier(reasonIdentifier)
        Text(message)
            .goFlyFont(GoFlyFont.footnote)
            .foregroundStyle(GoFlyTextColor.secondary)
    }

    private func preparationTitle(_ source: PreparedOperationSource) -> String {
        switch source {
        case .start: "operation.preparingService"
        case .point, .route, .joystick: "operation.preparingMove"
        }
    }

    private func sourceSummary(_ source: PreparedOperationSource) -> some View {
        let text: String
        switch source {
        case .start: text = goFlyString("operation.startSummary")
        case .point(let intent):
            text = goFlyLocalizedFormat(goFlyString("operation.destination"), intent.candidate.place.title)
        case .route(let intent):
            let destination: String
            if case .place(let place) = intent.draft.destination?.value { destination = place.title }
            else { destination = intent.route.end.displayText }
            text = goFlyLocalizedFormat(goFlyString("operation.destination"), destination)
        case .joystick: text = goFlyString("operation.joystickSummary")
        }
        return Text(text)
            .goFlyFont(GoFlyFont.subheadline)
            .foregroundStyle(GoFlyTextColor.secondary)
            .accessibilityIdentifier("operation.source")
    }

}
