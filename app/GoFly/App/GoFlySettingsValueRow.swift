import SwiftUI

/// Keep long titles and status values readable without shrinking text: one line when
/// both fit, otherwise the value moves under the title, as at accessibility sizes.
struct GoFlySettingsValueRow<Title: View, Value: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: Title
    let value: Value

    init(@ViewBuilder title: () -> Title, @ViewBuilder value: () -> Value) {
        self.title = title()
        self.value = value()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked(spacing: 8)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        title.lineLimit(1).fixedSize()
                        Spacer(minLength: 8)
                        value.lineLimit(1).fixedSize()
                    }
                    stacked(spacing: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func stacked(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            title
            value.multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
