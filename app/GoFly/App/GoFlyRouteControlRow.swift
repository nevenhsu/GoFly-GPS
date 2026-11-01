import SwiftUI

/// Round trip icon (Figma `icon / repeat`, 20 pt grid): two opposing arrows,
/// with a diagonal slash (`icon / repeat.slash`) when round trip is off.
struct GoFlyRouteRepeatIcon: View {
    let isOn: Bool
    var isEnabled = true

    var body: some View {
        GoFlyIcon(isOn ? .repeat : .repeatOff, size: 20, maximumSize: 28)
            .foregroundStyle(isEnabled ? (isOn ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                             : GoFlyTextColor.disabled)
    }
}

/// Direction icon (Figma `icon / direction.forward|reverse`, 20 pt grid): a
/// down arrow on the left and an up arrow on the right; the active direction is dark.
/// Forward: up arrow dark. Reverse: down arrow dark.
struct GoFlyVerticalArrowsIcon: View {
    let isReversed: Bool
    var isEnabled = true

    var body: some View {
        GoFlyIcon(isReversed ? .directionReverse : .directionForward, size: 20, maximumSize: 28)
            .foregroundStyle(isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
    }
}

/// Compact speed chip button without "km/h" unit (min width 68 pt).
struct GoFlySpeedChip: View {
    let speed: Int
    var action: () -> Void
    var isEnabled: Bool = true
    var identifier: String = "route.speedChip"
    /// Figma D6 uses a 36 pt chip with a trailing chevron; the joystick row keeps the compact 34 pt chip.
    var height: CGFloat = 34
    var showsChevron = false
    /// The wander range chip (Figma E1/E2 km chip) reuses this chip with another glyph, value and label.
    var icon: GoFlyIconAsset = .speed
    var valueText: String? = nil
    var accessibilityText: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                GoFlyIcon(icon, size: 16, maximumSize: 24)
                Text(valueText ?? "\(speed)")
                    .goFlyFont(GoFlyFont.footnoteEmphasis)
                    .monospacedDigit()
                    .lineLimit(1)
                if showsChevron {
                    GoFlyIcon(.chevronRight)
                        .goFlyIconSize(size: 10, maximum: 14)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 68, minHeight: height, maxHeight: height)
            .background(GoFlyStyle.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
            .goFlyShadow(.chip)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityText ?? goFlyLocalizedFormat(goFlyString("route.speedShort"), speed))
        .accessibilityIdentifier(identifier)
    }
}

/// Wireframe pure-icon control row for route execution mode (D3, D4).
struct GoFlyRouteControlRow: View {
    let isRoundTrip: Bool
    let isReversed: Bool
    let speed: Int
    var canToggleRoundTrip: Bool = true
    var canToggleDirection: Bool = true
    var canChangeSpeed: Bool = true
    var onToggleRoundTrip: () -> Void
    var onToggleDirection: () -> Void
    var onSpeedTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Round trip: Figma D6 ⇄, primary when on, secondary when off.
            Button(action: onToggleRoundTrip) {
                GoFlyRouteRepeatIcon(isOn: isRoundTrip, isEnabled: canToggleRoundTrip)
                    .frame(width: 36, height: 36)
                    .background(canToggleRoundTrip ? GoFlyStyle.routeControlSurface : GoFlyStyle.disabledSurface,
                                in: Circle())
                    .overlay {
                        if canToggleRoundTrip {
                            Circle().strokeBorder(GoFlyStyle.routeControlBorder, lineWidth: 0.5)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleRoundTrip)
            .accessibilityLabel(goFlyString(isRoundTrip ? "route.roundTrip.on" : "route.roundTrip.off"))
            .accessibilityIdentifier("route.control.repeat")

            // Direction button: only while round trip is on; single trip is always forward.
            if isRoundTrip {
                Button(action: onToggleDirection) {
                    GoFlyVerticalArrowsIcon(isReversed: isReversed, isEnabled: canToggleDirection)
                        .frame(width: 36, height: 36)
                        .background(canToggleDirection ? GoFlyStyle.routeControlSurface : GoFlyStyle.disabledSurface,
                                    in: Circle())
                        .overlay {
                            if canToggleDirection {
                                Circle().strokeBorder(GoFlyStyle.routeControlBorder, lineWidth: 0.5)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canToggleDirection)
                .accessibilityLabel(goFlyString(isReversed ? "route.direction.reverse" : "route.direction.forward"))
                .accessibilityIdentifier("route.control.direction")
            }

            Spacer(minLength: 0)

            // Speed chip: pure number, 68 pt width
            GoFlySpeedChip(speed: speed, action: onSpeedTap, isEnabled: canChangeSpeed, height: 36, showsChevron: true)
        }
    }
}
