import SwiftUI
import UIKit

/// Figma D19–D22 bottom area of the favorites pages: the search section
/// (`Bottom bar / 搜尋`, 1 pt divider, 12 pt above and 28 pt below a 48 pt field) and,
/// in multi-select mode, the red delete button *above* it, 12 pt clear of the section.
struct GoFlyFavoritesBottomBar: View {
    /// Search section height without the safe area: 12 + 48 + 28.
    static let searchSectionHeight: CGFloat = 88
    /// A snackbar sits 12 pt above the search section (D22).
    static let snackbarOffset: CGFloat = searchSectionHeight + 12

    let placeholder: String
    @Binding var query: String
    let searchIdentifier: String
    /// Non-nil only while selecting: the delete button title.
    var deleteTitle: String? = nil
    var deleteEnabled = true
    var deleteIdentifier = "favorites.deleteSelected"
    var onDelete: () -> Void = { }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let deleteTitle {
                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        GoFlyTrashIcon(size: 17)
                        Text(deleteTitle)
                    }
                }
                .buttonStyle(GoFlyButtonStyle(variant: .danger, size: .medium))
                .disabled(!deleteEnabled)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier(deleteIdentifier)
            }
            searchSection
        }
    }

    private var searchSection: some View {
        HStack(spacing: 8) {
            GoFlyIcon(GoFlySymbols.search)
                .goFlyIconSize(size: 17)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($focused)
                .accessibilityIdentifier(searchIdentifier)
            if !query.isEmpty {
                Button { query = "" } label: {
                    GoFlyIcon(.close)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.clear"))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(minHeight: 48)
        .goFlySearchField(isFocused: focused)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(GoFlyStyle.tabBarSurface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { GoFlyStyle.tabSeparator.frame(height: 1) }
    }
}
