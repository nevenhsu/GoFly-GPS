import GoFlyCore
import SwiftUI

struct GoFlySpeedSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let speed: RouteSpeed
    var canEdit: Bool = true
    var onSpeedChanged: (RouteSpeed) -> Void
    var onDismiss: () -> Void

    private let presets: [Int] = RouteSpeed.presets.map(\.kilometersPerHour)

    /// Flat colorful vector icons on a transparent background (orange, navy, mustard); they carry their own colors, so no light/dark variants are needed.
    private func presetIcon(for preset: Int) -> GoFlyIconAsset? {
        switch preset {
        case 5: return .speedWalk
        case 25: return .speedBicycle
        case 50: return .speedScooter
        case 100: return .speedCar
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
            // Current Speed Readout in a single row
            HStack(alignment: .firstTextBaseline) {
                Text(goFlyString("route.speedCurrent"))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(speed.kilometersPerHour)")
                        .goFlyFont(GoFlyFont.metric)
                        .monospacedDigit()
                        .foregroundStyle(GoFlyTextColor.primary)
                    Text(goFlyString("route.speedUnit"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
                .accessibilityIdentifier("route.speed.value")
            }
            .padding(.vertical, 4)

            // Preset Chips with icons
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    let isSelected = speed.kilometersPerHour == preset
                    Button {
                        if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: preset) {
                            onSpeedChanged(newSpeed)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let icon = presetIcon(for: preset) {
                                GoFlyIcon(icon, size: 20)
                                    .accessibilityHidden(true)
                            }
                            Text("\(preset)")
                        }
                        .goFlyFont(GoFlyFont.footnoteEmphasis)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            colorScheme == .dark && isSelected
                                ? GoFlyThemeColor.surfaceControl
                                : GoFlyThemeColor.surfaceCard,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                isSelected ? GoFlyThemeColor.iconAccent : GoFlyThemeColor.lineBorder,
                                lineWidth: 1
                            )
                        }
                        .foregroundStyle(isSelected ? GoFlyTextColor.accent : GoFlyTextColor.primary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityIdentifier("route.speed.preset.\(preset)")
                }
            }

            // Slider with min/max labels below
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(speed.kilometersPerHour) },
                        set: { value in
                            if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: Int(value.rounded())) {
                                onSpeedChanged(newSpeed)
                            }
                        }
                    ),
                    in: 1...120
                )
                .tint(GoFlyStyle.primary)
                .disabled(!canEdit)
                .accessibilityIdentifier("route.speed")

                HStack {
                    Text("1 \(goFlyString("route.speedUnit"))")
                        .goFlyFont(GoFlyFont.caption)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    Spacer()
                    Text("120 \(goFlyString("route.speedUnit"))")
                        .goFlyFont(GoFlyFont.caption)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
            }
            .padding(.top, 8) // 16 stack spacing + 8 = 24 under the preset chips

            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            // Bottom Confirm Button
            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .accessibilityIdentifier("route.speed.confirm")
            .padding(.top, 20)
            .padding(.horizontal, 20)
            // The sheet adds about 31 pt below its content; 9 pt more gives the 40 pt bottom margin.
            .padding(.bottom, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
    }
}
