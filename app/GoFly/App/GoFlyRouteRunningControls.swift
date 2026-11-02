import SwiftUI

/// Figma D6 bottom controls: position label + percent, 6 pt progress, the 36 pt
/// control row (round trip, direction, speed) and 結束 / 暫停, 20 pt apart.
struct GoFlyRouteRunningControls: View {
    let title: String
    let fraction: Double
    let isRoundTrip: Bool
    let isReversed: Bool
    let speed: Int
    var canToggleRoundTrip = true
    var canToggleDirection = true
    var canChangeSpeed = true
    var isPaused = false
    /// D10: an interrupted route's primary button retries instead of resuming.
    var isInterrupted = false
    var canPlayback = true
    var canEnd = true
    var onToggleRoundTrip: () -> Void = { }
    var onToggleDirection: () -> Void = { }
    var onSpeedTap: () -> Void = { }
    var onPlayback: () -> Void = { }
    var onEnd: () -> Void = { }

    /// D6 single-trip label: remaining time at the current speed, rounded up
    /// to the minute. Round trip has no end, so it keeps the position label.
    static func remainingTitle(_ remaining: Duration?) -> String {
        guard let remaining else { return goFlyString("route.progress") }
        let minutes = Int(ceil(Double(max(0, remaining.components.seconds)) / 60))
        return minutes >= 60
            ? goFlyLocalizedFormat(goFlyString("route.remaining.hours"), minutes / 60, minutes % 60)
            : goFlyLocalizedFormat(goFlyString("route.remaining.minutes"), minutes)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .goFlyFont(GoFlyFont.footnote)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    Spacer(minLength: 8)
                    Text(min(max(fraction, 0), 1), format: .percent.precision(.fractionLength(0)))
                        .goFlyFont(GoFlyFont.footnote).monospacedDigit()
                        .accessibilityIdentifier("route.position.value")
                }
                ProgressView(value: min(max(fraction, 0), 1), total: 1)
                    .progressViewStyle(GoFlyProgressStyle())
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("route.progress")
            }

            GoFlyRouteControlRow(
                isRoundTrip: isRoundTrip, isReversed: isReversed, speed: speed,
                canToggleRoundTrip: canToggleRoundTrip, canToggleDirection: canToggleDirection,
                canChangeSpeed: canChangeSpeed,
                onToggleRoundTrip: onToggleRoundTrip, onToggleDirection: onToggleDirection, onSpeedTap: onSpeedTap
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { endButton.frame(width: 120); playbackButton }
                VStack(spacing: 12) { endButton; playbackButton }
            }
        }
    }

    private var endButton: some View {
        Button(action: onEnd) {
            GoFlyIconLabel(title: goFlyString("execution.end"), icon: GoFlySymbols.close)
                .lineLimit(1)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .neutral))
        .disabled(!canEnd)
        .accessibilityIdentifier("route.cancel")
    }

    private var playbackButton: some View {
        Button(action: onPlayback) {
            GoFlyIconLabel(
                title: goFlyString(isInterrupted ? "common.continue" : (isPaused ? "route.resume" : "route.pause")),
                icon: isPaused ? GoFlySymbols.play : GoFlySymbols.pause)
                .lineLimit(1)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .primary))
        .goFlySteadyDisabled(!canPlayback)
        .accessibilityIdentifier(isInterrupted ? "route.retry" : (isPaused ? "route.resume" : "route.pause"))
    }
}
