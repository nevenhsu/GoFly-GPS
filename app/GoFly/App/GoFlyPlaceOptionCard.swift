import GoFlyCore
import SwiftUI

struct GoFlyFavoriteStar: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let place: MapPlace
    var identifier: String
    /// Location cards use the shared 44 pt icon-only button size.
    var isCardAction = false
    /// List rows draw the icon inside a filled circle (Figma B2 favorite row).
    var circleDiameter: CGFloat? = nil
    /// Show the editor's Delete action for existing favorites opened from this star.
    var allowsDelete = false
    @State private var showingEditor = false

    var body: some View {
        Button { showingEditor = true } label: {
            if isCardAction {
                GoFlyStarIcon(size: 22, filled: favorites.isFavorite(place))
                    .goFlyIconButtonChrome(diameter: 44)
            } else if let circleDiameter {
                GoFlyStarIcon(size: 15, filled: favorites.isFavorite(place))
                    .goFlyIconButtonChrome(diameter: circleDiameter, showsBorder: false)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            } else {
                GoFlyStarIcon(size: 18, filled: favorites.isFavorite(place))
                    .goFlyIconButtonChrome(diameter: 44)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(favorites.canMutate ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
        .disabled(!favorites.canMutate)
        .accessibilityLabel(goFlyString(favorites.canMutate
            ? (favorites.isFavorite(place) ? "favorites.editLabel" : "favorites.add") : "favorites.title"))
        .accessibilityValue(goFlyString(favorites.canMutate
            ? (favorites.isFavorite(place) ? "favorites.saved" : "favorites.notSaved") : "favorites.unavailable"))
        .accessibilityIdentifier(identifier)
        .goFlyTracksSystemPresentation(showingEditor, id: "favoriteStar.\(identifier)")
        .sheet(isPresented: $showingEditor) {
            GoFlyFavoriteEditorSheet(place: place, initialLabel: favorites.favorite(for: place)?.label,
                                     allowsDelete: allowsDelete, onDismiss: { showingEditor = false })
        }
    }
}

struct GoFlyFavoriteFailureNotice: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    var maximumHeight: CGFloat? = nil
    @State private var contentHeight: CGFloat = 64

    var body: some View {
        if let failure {
            if let maximumHeight {
                ScrollView {
                    notice(failure)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, maximumHeight))
            } else {
                notice(failure)
            }
        }
    }

    private func notice(_ failure: FavoritePlacesFailure) -> some View {
        GoFlyStatusBanner(tone: .danger, title: goFlyIssueTitle(for: failure.rawValue), message: goFlyString(failure.rawValue),
            onDismiss: favorites.canMutate ? { favorites.clearError() } : nil,
            identifier: "favorites.error")
    }

    private var failure: FavoritePlacesFailure? {
        if case .blocked(let failure) = favorites.loadState { return failure }
        return favorites.error
    }
}
