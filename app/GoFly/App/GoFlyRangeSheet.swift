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
            .padding(.horizontal, GoFlyStyle.Layout.sheetHorizontal)
            .padding(.top, GoFlyStyle.Layout.compactSheetTop)
            .padding(.bottom, GoFlyStyle.Spacing.sm)

            Spacer(minLength: 0)

            Button(action: onDismiss) { Text(goFlyString("common.doneSetting")) }
                .buttonStyle(GoFlyButtonStyle(variant: .primary))
                .accessibilityIdentifier("wander.range.confirm")
                .padding(.top, GoFlyStyle.Spacing.xl)
                .padding(.horizontal, GoFlyStyle.Layout.sheetHorizontal)
                .padding(.bottom, GoFlyStyle.Layout.compactSheetButtonBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(GoFlyStyle.Layout.compactSheetDetentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.cardSurface)
    }

    private func presetChip(_ preset: WanderRadius) -> some View {
        GoFlyPresetChip(isSelected: radius == preset) {
            onRadiusChanged(preset)
        } label: {
            Text("\(preset.kilometersText) km")
        }
        .accessibilityIdentifier("wander.range.preset.\(preset.kilometersText)")
    }
}
