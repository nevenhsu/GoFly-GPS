import GoFlyCore
import SwiftUI

struct GoFlyFavoritesView: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    var candidate: MapPlace?
    var onSelect: (MapPlace) -> Void
    var onSearch: () -> Void
    var onDismiss: () -> Void
    @State private var editing: FavoritePlace?
    @State private var query = ""
    @State private var selecting = false
    @State private var selected: Set<FavoritePlaceKey> = []
    @State private var snackbar: GoFlySnackbarMessage?

    private var visible: [FavoritePlace] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.favorites.filter {
            text.isEmpty || [$0.displayTitle, $0.place.title, $0.place.address ?? "", $0.place.coordinate.displayText]
                .contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .goFlyDismissesKeyboardOnTap()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    failureNotice
                    // Like favorite routes, the empty state sits on the page; only rows get the card.
                    if favorites.loadState == .ready, visible.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.favorite,
                            message: goFlyString(query.isEmpty ? "favorites.empty" : "favorites.noMatches"))
                            .padding(.vertical, 24)
                            .accessibilityIdentifier("favorites.empty")
                    }
                    if !visible.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible) { favorite in
                                let showsSeparator = favorite.id != visible.last?.id
                                GoFlyListRow(minimumHeight: 64,
                                             separatorLeadingInset: showsSeparator ? 60 : nil,
                                             separatorTrailingInset: 12) {
                                    row(favorite)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                        .goFlyCard(radius: GoFlyStyle.cardRadius)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, GoFlyStyle.favoriteListTopSpacing)
            }
            .scrollDismissesKeyboard(.immediately)
            .goFlyDismissesKeyboardOnTap()
            .accessibilityIdentifier("favorites.content")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GoFlyFavoritesBottomBar(
                    placeholder: goFlyString("favorites.searchSaved"), query: $query,
                    searchIdentifier: "favorites.search",
                    deleteTitle: selecting ? goFlyLocalizedFormat(goFlyString("favorites.deleteCount"), selected.count) : nil,
                    deleteEnabled: !selected.isEmpty && favorites.canMutate,
                    deleteIdentifier: "favorites.deleteSelected",
                    onDelete: { delete(selected); selecting = false })
            }
        }
        .background(GoFlyStyle.canvas)
        .goFlySnackbar($snackbar, bottomPadding: GoFlyFavoritesBottomBar.snackbarOffset)
        .goFlyTracksSystemPresentation(editing != nil, id: "favorites.editor")
        .sheet(item: $editing) { favorite in
            GoFlyFavoriteEditorSheet(place: favorite.place, initialLabel: favorite.label, onDismiss: { editing = nil }) {
                delete([favorite.key])
                if !favorites.isFavorite(favorite.place) { editing = nil }
            }
        }
    }

    private var header: some View {
        GoFlySheetHeader(title: selecting
                         ? goFlyLocalizedFormat(goFlyString("favorites.selectedCount"), selected.count)
                         : goFlyString("favorites.title")) {
            Button {
                if selecting { selecting = false; selected.removeAll() }
                else { onDismiss() }
            } label: {
                Group {
                    if selecting {
                        Text(goFlyString("favorites.cancel"))
                            .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    } else {
                        GoFlyIconLabel(title: goFlyString("common.back"), icon: .chevronLeft)
                            .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    }
                }
                .foregroundStyle(GoFlyTextColor.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorites.dismiss")
        } trailing: {
            if selecting {
                Button {
                    let keys = Set(visible.map(\.key))
                    if keys.isSubset(of: selected) { selected.subtract(keys) }
                    else { selected.formUnion(keys) }
                } label: {
                    Text(goFlyString("favorites.selectAll"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.selectAll")
            } else {
                Button {
                    selecting = true
                    selected.removeAll()
                } label: {
                    Text(goFlyString("favorites.select"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.select"))
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.select")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder private var failureNotice: some View {
        if let failure = failure {
            let button = goFlyIssueButton(for: failure.rawValue, retry: { favorites.reload() })
            GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue),
                actionTitle: button.title, onAction: button.action,
                onDismiss: favorites.canMutate ? { favorites.clearError() } : nil,
                identifier: "favorites.error")
                .padding(.vertical, 12)
        }
    }

    private var failure: FavoritePlacesFailure? {
        if case .blocked(let failure) = favorites.loadState { return failure }
        return favorites.error
    }

    private func row(_ favorite: FavoritePlace) -> some View {
        HStack(spacing: 8) {
            if selecting {
                Button {
                    toggleSelection(favorite.key)
                } label: {
                    GoFlyCheckboxIcon(selected: selected.contains(favorite.key), size: 22)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(goFlyString("favorites.select"))
                .accessibilityAddTraits(selected.contains(favorite.key) ? .isSelected : [])
                .accessibilityIdentifier("favorites.checkbox.\(favorite.place.coordinate.displayText)")
            } else {
                // Same editor as ⋯ (2026-10-26).
                Button { editing = favorite } label: {
                    GoFlyStarIcon(size: 16, filled: true)
                        .goFlyIconButtonChrome(diameter: 36, showsBorder: false)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.editLabel"))
                .accessibilityIdentifier("favorites.star.\(favorite.place.coordinate.displayText)")
            }
            Button {
                if selecting { toggleSelection(favorite.key) }
                else { onSelect(favorite.place) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.displayTitle).goFlyFont(GoFlyFont.body)
                    if let subtitle = favoriteSubtitle(favorite) {
                        Text(subtitle)
                            .goFlyFont(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected.contains(favorite.key)
                || candidate.flatMap(FavoritePlaceKey.init(place:)) == favorite.key ? .isSelected : [])
            .accessibilityIdentifier("favorites.place.\(favorite.place.coordinate.displayText)")
            if !selecting {
                Button {
                    editing = favorite
                } label: {
                    GoFlyIcon(.more).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.editLabel"))
                .accessibilityIdentifier("favorites.edit.\(favorite.place.coordinate.displayText)")
            }
        }
        .foregroundStyle(GoFlyTextColor.primary)
    }

    /// A coordinate favorite already shows its coordinate as the title; the
    /// Figma list shows one subtitle, never the same line twice.
    private func favoriteSubtitle(_ favorite: FavoritePlace) -> String? {
        if let address = favorite.place.address, !address.isEmpty { return address }
        let coordinate = favorite.place.coordinate.displayText
        return favorite.displayTitle == coordinate ? nil : coordinate
    }

    private func toggleSelection(_ key: FavoritePlaceKey) {
        if !selected.insert(key).inserted { selected.remove(key) }
    }

    private func delete(_ keys: Set<FavoritePlaceKey>) {
        let count = favorites.favorites.filter { keys.contains($0.key) }.count
        guard favorites.delete(keys) else { return }
        selected.subtract(keys)
        snackbar = GoFlySnackbarMessage(
            text: goFlyLocalizedFormat(goFlyString("favorites.deletedCount"), count),
            actionTitle: goFlyString("common.undo"), action: { _ = favorites.undoDelete() })
    }
}
