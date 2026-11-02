import GoFlyCore
import SwiftUI

/// C2 sheet: modal for adding or editing a favorite place (plan C2).
/// Displays a dismiss/cancel button, title "編輯最愛", optional red "刪除" button,
/// editable label field, place address/coordinates box, and bottom primary "儲存" button.
/// Star entry points may enable Delete for an existing favorite; tapping a star only opens this sheet.
struct GoFlyFavoriteEditorSheet: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @Environment(\.colorScheme) private var colorScheme
    let place: MapPlace
    var onDismiss: () -> Void
    var onDelete: (() -> Void)? = nil
    var allowsDelete = true
    @State private var draft: String
    @State private var fallbackLabel = FavoriteLabelDefaults.defaultName()
    @FocusState private var focused: Bool

    init(place: MapPlace, initialLabel: String? = nil, allowsDelete: Bool = true,
         onDismiss: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.place = place
        self.allowsDelete = allowsDelete
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _draft = State(initialValue: initialLabel ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let failure = favorites.error {
                        GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue), identifier: "favorites.error")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(goFlyString("favorites.label"), text: $draft,
                                      prompt: Text(goFlyString("favorites.label")))
                                .goFlyFont(GoFlyFont.body)
                                .focused($focused).submitLabel(.done)
                                .onSubmit { focused = false }
                                .accessibilityIdentifier("favorites.editor.label")
                            Button { draft = "" } label: {
                                GoFlyIcon(.close).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityLabel(goFlyString("search.clear"))
                            .accessibilityIdentifier("favorites.editor.clear")
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .goFlySearchField(isFocused: focused)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(place.address ?? place.title).goFlyFont(GoFlyFont.subheadline)
                        Text(coordinateSummary)
                            .goFlyFont(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? GoFlyStyle.locationCardSurface : GoFlyStyle.canvas,
                                in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("favorites.editor.info")

                    // Keep 40 pt above the button from the preceding VStack gap + top inset, and 40 pt below per the latest C2 spacing update.
                    Button {
                        if favorites.save(place: place, label: FavoriteLabelDefaults.resolved(draft, fallback: fallbackLabel)) {
                            onDismiss()
                        }
                    } label: {
                        Text(goFlyString("favorites.save"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoFlyButtonStyle(variant: .primary))
                    .disabled(!favorites.canMutate)
                    .padding(.top, 24)
                    .padding(.bottom, GoFlyStyle.favoriteEditorSaveBottomSpacing)
                    .accessibilityIdentifier("favorites.editor.save")
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("favorites.editor.form")
        }
        // 347 pt with the 11 pt button inset leaves 40 pt below Save (measured: 367 pt with 40 pt left 89 pt).
        .presentationDetents([.height(347), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .onAppear {
            if draft.isEmpty, let fav = favorites.favorite(for: place), let l = fav.label {
                draft = l
            }
        }
    }

    private var isFavorite: Bool {
        favorites.isFavorite(place)
    }

    private var coordinateSummary: String {
        String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"),
               place.coordinate.latitude, place.coordinate.longitude)
    }

    private var header: some View {
        GoFlySheetHeader(title: nil) {
            Button {
                favorites.clearError()
                onDismiss()
            } label: {
                Text(goFlyString("favorites.cancel"))
                    .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("favorites.editor.cancel")
        } trailing: {
            if allowsDelete, isFavorite {
                Button {
                    if let onDelete {
                        onDelete()
                    } else {
                        favorites.delete(place: place)
                        onDismiss()
                    }
                } label: {
                    Text(goFlyString("favorites.delete"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.danger)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("favorites.editor.delete")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
