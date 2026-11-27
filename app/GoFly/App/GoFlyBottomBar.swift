import GoFlyCore
import SwiftUI

/// Three equal-width mode tabs (plan 3). Hidden entirely in execution mode and
/// on full-screen pages; switching tabs only changes what is browsed.
/// Figma `TabBar / 瞬移・路線・搖桿（等寬）`: 83 pt including the home indicator.
struct GoFlyBottomBar: View {
    @Binding var selection: SessionMapMode
    var bottomInset: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionMapMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 1) {
                        GoFlyTabIcon(mode: mode, selected: selection == mode, size: 25)
                        Text(goFlyString("mode.\(mode.rawValue)"))
                            .goFlyFont(GoFlyFont.micro)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, minHeight: 49, alignment: .top)
                    .foregroundStyle(selection == mode ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("mode.\(mode.rawValue)"))
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityIdentifier("mode.\(mode.rawValue)")
            }
        }
        .padding(.bottom, bottomInset)
        .goFlyTopHairline()
        .background(GoFlyStyle.overlayPanelSurface.ignoresSafeArea(edges: .bottom))
        // Chrome caps Dynamic Type the way UIKit tab bars do; the labels stay
        // legible and equal-width even at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goFlyString("mode.title"))
        .accessibilityIdentifier("map.bottomBar")
    }

}
