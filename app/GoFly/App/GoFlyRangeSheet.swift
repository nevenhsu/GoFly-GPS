import GoFlyCore
import SwiftUI

extension WanderRadius {
    /// Locale-aware kilometres with at most one decimal ("0.5", "5", "100").
    var kilometersText: String {
        kilometers.formatted(.number.precision(.fractionLength(0...1)))
    }

    static let presets: [WanderRadius] = [0.5, 5, 20, 100].map { WanderRadius(kilometers: $0) }
}

/// Figma E2.b: sets the wander radius around the range anchor. Shares the
/// speed sheet's layout so the two settings read the same.
struct GoFlyRangeSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let radius: WanderRadius
    var onRadiusChanged: (WanderRadius) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goFlyString("wander.range.radius"))
                        .goFlyFont(GoFlyFont.body)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(radius.kilometersText)
                            .goFlyFont(GoFlyFont.metric)
                            .monospacedDigit()
                            .foregroundStyle(GoFlyTextColor.primary)
                        Text("km")
                            .goFlyFont(GoFlyFont.subheadlineEmphasis)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("wander.range.value")
                }
                .padding(.vertical, 4)

                HStack(spacing: 8) {
                    ForEach(WanderRadius.presets, id: \.kilometers) { preset in
                        presetChip(preset)
                    }
                }

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { radius.kilometers },
                            set: { onRadiusChanged(WanderRadius(kilometers: $0)) }
                        ),
                        in: WanderRadius.minimumKilometers...WanderRadius.maximumKilometers,
                        step: 0.1
                    )
                    .tint(GoFlyStyle.primary)
                    .accessibilityLabel(goFlyString("wander.range.radius"))
                    .accessibilityIdentifier("wander.range.slider")

                    HStack {
                        Text("\(WanderRadius(kilometers: WanderRadius.minimumKilometers).kilometersText) km")
                        Spacer()
                        Text("\(WanderRadius(kilometers: WanderRadius.maximumKilometers).kilometersText) km")
                    }
                    .goFlyFont(GoFlyFont.caption)
                    .foregroundStyle(GoFlyTextColor.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            Button(action: onDismiss) { Text(goFlyString("common.doneSetting")) }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .accessibilityIdentifier("wander.range.confirm")
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
    }

    private func presetChip(_ preset: WanderRadius) -> some View {
        let isSelected = radius == preset
        return Button { onRadiusChanged(preset) } label: {
            Text("\(preset.kilometersText) km")
                .goFlyFont(GoFlyFont.footnoteEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    colorScheme == .dark && isSelected ? GoFlyThemeColor.surfaceControl : GoFlyThemeColor.surfaceCard,
                    in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? GoFlyThemeColor.iconAccent : GoFlyThemeColor.lineBorder,
                                           lineWidth: 1)
                }
                .foregroundStyle(isSelected ? GoFlyTextColor.accent : GoFlyTextColor.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wander.range.preset.\(preset.kilometersText)")
    }
}
