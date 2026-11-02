import SwiftUI
import UIKit

struct GoFlyMapSearchBar: View {
    let text: String
    let hasContent: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    let onPaste: (String) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button(action: onSearch) {
                    HStack(spacing: 10) {
                        GoFlyIcon(GoFlySymbols.search)
                            .goFlyIconSize(size: 20, maximum: 20)
                            .foregroundStyle(GoFlyTextColor.secondary)
                        Text(text)
                            .goFlyFont(GoFlyFont.body)
                            .foregroundStyle(hasContent ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.placeholder"))
                .accessibilityValue(hasContent ? text : "")
                .accessibilityHint(goFlyString("map.searchHint"))
                .accessibilityIdentifier("map.searchBar")

                // Both controls stay mounted: rebuilding the system paste control on
                // every clear sometimes leaves it undrawn. It is hidden with
                // `isHidden`, never opacity, which would invalidate its taps.
                ZStack {
                    GoFlyPasteButton(accessibilityLabel: goFlyString("search.paste"),
                                     accessibilityIdentifier: "map.searchPaste",
                                     isVisible: !hasContent,
                                     onPaste: onPaste)
                    Button(action: onClear) {
                        GoFlyIcon(GoFlySymbols.clearSearch)
                            .goFlyIconSize(size: 16, maximum: 18)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("search.clear"))
                    .accessibilityIdentifier("map.searchClear")
                    .opacity(hasContent ? 1 : 0)
                    .allowsHitTesting(hasContent)
                    .accessibilityHidden(!hasContent)
                }
                .padding(.trailing, 6)
            }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            // The shadow belongs to the card only: on the whole row SwiftUI also
            // shadows each child, ringing the system paste capsule in light mode.
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GoFlyThemeColor.surfaceInput)
                    .goFlyShadow(.floating)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GoFlyStyle.fieldBorder, lineWidth: 1)
            }

            Button(action: onSettings) {
                // Figma 04 · Settings / 設定 > icon / gear.
                GoFlyIcon(.gear, size: 22)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("settings.title"))
            .accessibilityIdentifier("map.settings")
            .background(GoFlyStyle.iconButtonSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GoFlyStyle.iconButtonBorder, lineWidth: 0.5)
            }
            .goFlyShadow(.floating)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}
