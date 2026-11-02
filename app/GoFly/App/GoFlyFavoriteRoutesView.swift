import GoFlyCore
import SwiftUI

struct GoFlyFavoriteRoutesView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var onDismiss: () -> Void

    @State private var editing: FavoriteRouteRecord?
    @State private var query = ""
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadRequest: UUID?
    @State private var loadFailureKey: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visible: [FavoriteRouteRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.records.filter {
            text.isEmpty || [
                $0.label ?? "",
                $0.startTitle ?? "",
                $0.endTitle ?? "",
                $0.displayFilename ?? "",
                $0.start.displayText,
                $0.end.displayText
            ].contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .goFlyDismissesKeyboardOnTap()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GoFlyFavoriteRouteFailureNotice(localErrorKey: loadFailureKey)
                    if favorites.loadState == .loading {
                        ProgressView(goFlyString("favoriteRoutes.loading"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if favorites.loadState == .ready, visible.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.route,
                                        message: goFlyString(query.isEmpty ? "favoriteRoutes.empty" : "favoriteRoutes.noMatches"))
                            .padding(.vertical, 24)
                            .accessibilityIdentifier("favoriteRoutes.empty")
                    }
                    if favorites.isBusy || favorites.isValidatingSelection {
                        ProgressView(goFlyString(favorites.isValidatingSelection ? "favoriteRoutes.validating" : "favoriteRoutes.working"))
                            .goFlyFont(GoFlyFont.body)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("favoriteRoutes.working")
                    }
                    if !visible.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                                GoFlyListRow(
                                    minimumHeight: 64,
                                    separatorLeadingInset: index < visible.count - 1 ? 52 : nil,
                                    separatorTrailingInset: 4
                                ) {
                                    row(record)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .background(GoFlyStyle.cardSurface,
                                    in: RoundedRectangle(cornerRadius: GoFlyStyle.cardRadius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: GoFlyStyle.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: GoFlyStyle.cardRadius, style: .continuous)
                                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("favoriteRoutes.card")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.immediately)
            .goFlyDismissesKeyboardOnTap()
            .accessibilityIdentifier("favoriteRoutes.content")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GoFlyFavoritesBottomBar(
                    placeholder: goFlyString("favoriteRoutes.searchSaved"), query: $query,
                    searchIdentifier: "favoriteRoutes.search",
                    deleteTitle: selecting ? goFlyLocalizedFormat(goFlyString("favorites.deleteCount"), selected.count) : nil,
                    deleteEnabled: !selected.isEmpty && favorites.canMutate,
                    deleteIdentifier: "favoriteRoutes.deleteSelected",
                    onDelete: { delete(selected) })
            }
        }
        .background(GoFlyStyle.canvas)
        .goFlySnackbar($snackbar, bottomPadding: GoFlyFavoritesBottomBar.snackbarOffset)
        .goFlyTracksSystemPresentation(editing != nil, id: "favoriteRoutes.editor")
        .sheet(item: $editing) { record in
            GoFlyFavoriteRouteLabelEditor(record: record, onDismiss: { editing = nil }) {
                delete(Set([record.id]))
                editing = nil
            }
        }
        .onAppear { controller.invalidateFavoriteLoadAdmission() }
        .onDisappear { invalidateLoad() }
    }

    private var canSelect: Bool {
        controller.canEdit && favorites.loadState == .ready && !favorites.isBusy
    }

    private var header: some View {
        GoFlySheetHeader(title: selecting
                         ? goFlyLocalizedFormat(goFlyString("favorites.selectedCount"), selected.count)
                         : goFlyString("favoriteRoutes.title")) {
            Button {
                if selecting { selecting = false; selected.removeAll() }
                else {
                    invalidateLoad()
                    onDismiss()
                }
            } label: {
                Group {
                    if selecting {
                        Text(goFlyString("favorites.cancel"))
                    } else {
                        GoFlyIconLabel(title: goFlyString("mode.route"), icon: .chevronLeft)
                            .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyTextColor.accent)
            .accessibilityIdentifier("favoriteRoutes.dismiss")
        } trailing: {
            if selecting {
                Button {
                    let ids = Set(visible.map(\.id))
                    if ids.isSubset(of: selected) { selected.subtract(ids) }
                    else { selected.formUnion(ids) }
                } label: {
                    Text(goFlyString("favorites.selectAll"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favoriteRoutes.selectAll")
            } else {
                Button {
                    selecting = true
                    selected.removeAll()
                } label: {
                    Text(goFlyString("favorites.select"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate || favorites.records.isEmpty)
                .accessibilityIdentifier("favoriteRoutes.select")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func row(_ record: FavoriteRouteRecord) -> some View {
        HStack(spacing: 8) {
            if selecting {
                Button {
                    toggleSelection(record.id)
                } label: {
                    GoFlyCheckboxIcon(selected: selected.contains(record.id), size: 22)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(goFlyString("favorites.select"))
                .accessibilityIdentifier("favoriteRoutes.checkbox.\(record.id.uuidString)")
            } else {
                // Same editor as ⋯ (2026-10-26).
                Button { edit(record) } label: {
                    GoFlyStarIcon(size: 16, filled: true)
                        .goFlyIconButtonChrome(diameter: 36, showsBorder: false)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityLabel(goFlyString("favoriteRoutes.editLabel"))
                .accessibilityIdentifier("favoriteRoutes.star.\(record.id.uuidString)")
            }

            Button {
                if selecting { toggleSelection(record.id) }
                else { load(record) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(record.label ?? goFlyFavoriteRouteEndpoints(record))
                        .goFlyFont(GoFlyFont.body)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(goFlyFavoriteRouteSubtitle(record))
                        .goFlyFont(GoFlyFont.footnote)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure = favorites.unavailable[record.id] {
                        Text(goFlyString(failure.localizationKey))
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.danger)
                            .accessibilityIdentifier("favoriteRoutes.unavailable.\(record.id.uuidString)")
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(canSelect && favorites.unavailable[record.id] == nil)
            .disabled(!canSelect || favorites.unavailable[record.id] != nil)
            .accessibilityIdentifier("favoriteRoutes.record.\(record.id.uuidString)")

            if !selecting {
                Button { edit(record) } label: {
                    GoFlyIcon(.more, size: 20)
                        .goFlyIconForeground(enabledColor: GoFlyTextColor.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityLabel(goFlyString("favoriteRoutes.editLabel"))
                .accessibilityIdentifier("favoriteRoutes.edit.\(record.id.uuidString)")
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if !selected.insert(id).inserted { selected.remove(id) }
    }

    private func delete(_ ids: Set<UUID>) {
        invalidateLoad()
        let count = ids.count
        Task {
            if await favorites.delete(ids) {
                if let loadedID = controller.loadedFavoriteRecordID, ids.contains(loadedID) {
                    controller.setLoadedFavoriteRecordID(nil)
                }
                selected.subtract(ids)
                selecting = false
                snackbar = GoFlySnackbarMessage(
                    text: goFlyLocalizedFormat(goFlyString("favoriteRoutes.deletedCount"), count),
                    actionTitle: goFlyString("common.undo"),
                    action: {
                        invalidateLoad()
                        Task { _ = await favorites.undoDelete() }
                    }
                )
            }
        }
    }

    private func invalidateLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadRequest = nil
        controller.invalidateFavoriteLoadAdmission()
    }

    private func load(_ record: FavoriteRouteRecord) {
        guard canSelect else { return }
        invalidateLoad()
        guard let admission = controller.beginFavoriteLoad() else { return }
        let request = UUID()
        loadRequest = request
        loadFailureKey = nil
        loadTask = Task {
            await favorites.select(record.id)
            guard !Task.isCancelled, loadRequest == request,
                  favorites.loadState == .ready, favorites.selectedID == record.id,
                  let snapshot = favorites.selectedSnapshot, snapshot.record.id == record.id,
                  controller.favoriteLoadAdmissionRevision == admission else { return }
            if controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: admission) {
                controller.setLoadedFavoriteRecordID(record.id)
                onDismiss()
            } else {
                loadFailureKey = controller.error?.localizationKey
            }
        }
    }

    private func edit(_ record: FavoriteRouteRecord) {
        guard favorites.canMutate else { return }
        invalidateLoad()
        loadFailureKey = nil
        editing = record
    }
}

struct GoFlyFavoriteRouteFailureNotice: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    var localErrorKey: String? = nil

    var body: some View {
        if let key {
            let button = goFlyIssueButton(for: key, retry: { Task { await favorites.load() } })
            GoFlyStatusBanner(tone: .danger, title: goFlyIssueTitle(for: key), message: goFlyString(key), actionTitle: button.title,
                              onAction: button.action, identifier: "favoriteRoutes.error")
                .padding(.vertical, 8)
        }
    }
    private var key: String? {
        if case .blocked(let failure) = favorites.loadState { return failure.localizationKey }
        return localErrorKey ?? favorites.error?.localizationKey
    }
}

func goFlyFavoriteRouteEndpoints(_ record: FavoriteRouteRecord) -> String {
    (record.startTitle ?? record.start.displayText) + " → " + (record.endTitle ?? record.end.displayText)
}

/// D19 subtitle: endpoints (when a label is the title) joined with the point count.
@MainActor
func goFlyFavoriteRouteSubtitle(_ record: FavoriteRouteRecord) -> String {
    let count = goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
        ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count)
    guard record.label != nil else { return count }
    return goFlyFavoriteRouteEndpoints(record) + "・" + count
}
