import GoFlyCore
import SwiftUI

struct GoFlySaveFavoriteRouteView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: RouteExecutionController
    var currentLocationAvailable: Bool?
    var currentRouteOrigin: @MainActor () -> GeoCoordinate?
    var onDismiss: () -> Void

    @State private var label = ""
    @State private var fallbackLabel = FavoriteLabelDefaults.defaultName()
    @State private var saving = false
    @State private var localErrorKey: String?
    @State private var savedOmittingCurrent: FavoriteRouteRecord?
    @State private var saveTask: Task<Void, Never>?
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let saved = savedOmittingCurrent {
                        GoFlyStatusBanner(tone: .success, title: goFlyString("favoriteRoutes.savedOmittingCurrent"),
                                          identifier: "favoriteRoutes.save.omittedResult")
                        Text(goFlyFavoriteRouteEndpoints(saved)).goFlyFont(GoFlyFont.body)
                    } else {
                        GoFlyFavoriteRouteFailureNotice(localErrorKey: localErrorKey)

                        if saving {
                            ProgressView(goFlyString("favoriteRoutes.saving"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityIdentifier("favoriteRoutes.save.working")
                        }

                        if controller.draft.nodes.contains(where: { $0.value == .current }) {
                            Text(goFlyString(currentLocationAvailable == true
                                ? "favoriteRoutes.currentSnapshotHint" : "favoriteRoutes.currentOmittedHint"))
                                .goFlyFont(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField(goFlyString("favoriteRoutes.label"), text: $label,
                                          prompt: Text(goFlyString("favoriteRoutes.namePlaceholder")))
                                    .focused($focused)
                                    .submitLabel(.done)
                                    .onSubmit { focused = false }
                                    .disabled(saving)
                                    .accessibilityIdentifier("favoriteRoutes.save.label")
                                if !label.isEmpty {
                                    Button { label = "" } label: {
                                        GoFlyIcon(.close)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(GoFlyTextColor.secondary)
                                    .accessibilityLabel(goFlyString("search.clear"))
                                }
                            }
                            .padding(.leading, 16)
                            .frame(minHeight: 48)
                            .goFlySearchField(isFocused: focused)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(sourceSummary)
                                .goFlyFont(GoFlyFont.subheadlineEmphasis)
                                .foregroundStyle(GoFlyTextColor.primary)
                            Text(pointSummary)
                                .goFlyFont(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? GoFlyStyle.locationCardSurface : GoFlyStyle.canvas,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("favoriteRoutes.save.source")
                    }

                    // D20 / D7: 40 pt between the route info card and Save, and below Save per the user's D20 spacing update.
                    if savedOmittingCurrent != nil {
                        Button(goFlyString("favoriteRoutes.done"), action: onDismiss)
                            .buttonStyle(GoFlyButtonStyle(variant: .primary))
                            .padding(.top, 24)
                            .accessibilityIdentifier("favoriteRoutes.save.done")
                    } else {
                        Button(action: save) {
                            Text(goFlyString("favoriteRoutes.save"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GoFlyButtonStyle(variant: .primary))
                        .disabled(saving || !controller.canEdit || !favorites.canMutate || eligibilityError != nil)
                        .padding(.top, 24)
                        .accessibilityIdentifier("favoriteRoutes.save.confirm")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, GoFlyStyle.favoriteEditorSaveBottomSpacing)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("favoriteRoutes.save.content")
        }
        .presentationDetents([.height(max(200, headerHeight + contentHeight)), .large])
        .presentationDragIndicator(.visible)
        // Same opaque sheet as the place editor: a view background over the system
        // sheet material lets the Save button tint change with the detent.
        .presentationBackground(GoFlyStyle.surface)
        .interactiveDismissDisabled(saving)
        .onDisappear { saveTask?.cancel() }
    }

    private var header: some View {
        GoFlySheetHeader(title: nil) {
            Button(goFlyString("favoriteRoutes.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.save.cancel")
        } trailing: {
            EmptyView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var eligibilityError: String? {
        Self.eligibilityError(draft: controller.draft, currentLocationAvailable: currentLocationAvailable)
    }

    /// Fewer than two usable places cannot be saved; callers check this before opening the sheet.
    static func eligibilityError(draft: RouteDraft, currentLocationAvailable: Bool?) -> String? {
        guard draft.gpxSource == nil else { return nil }
        let count = draft.nodes.reduce(0) { count, node in
            switch node.value {
            case .place: count + 1
            case .current: count + (currentLocationAvailable == true ? 1 : 0)
            case .empty: count
            }
        }
        return count < 2 ? "favoriteRoutes.error.tooFewValidPlaces" : nil
    }

    private var sourceSummary: String {
        if let source = controller.draft.gpxSource {
            return source.displayFilename
        }
        func title(_ node: RouteNode?) -> String? {
            guard let node else { return nil }
            switch node.value {
            case .current: return goFlyString("route.currentLocation")
            case .place(let place): return place.title
            case .empty: return nil
            }
        }
        return [title(controller.draft.start), title(controller.draft.destination)].compactMap { $0 }.joined(separator: " → ")
    }

    private var pointSummary: String {
        if let source = controller.draft.gpxSource {
            return goFlyLocalizedFormat(goFlyString("favoriteRoutes.pointCount"), source.document.pointCount)
        }
        return goFlyLocalizedFormat(goFlyString("favoriteRoutes.placeCount"), controller.draft.nodes.filter { $0.value != .empty }.count)
    }

    private func save() {
        guard !saving, savedOmittingCurrent == nil, controller.canEdit, favorites.canMutate else { return }
        let draft = controller.draft
        let origin = currentRouteOrigin()
        let capturedLabel = FavoriteLabelDefaults.resolved(label, fallback: fallbackLabel)
        let candidate: FavoriteRouteSaveCandidate
        do { candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: origin) }
        catch {
            localErrorKey = (error as? FavoriteRoutesFailure)?.localizationKey ?? "favoriteRoutes.error.unavailable"
            return
        }
        localErrorKey = nil
        saving = true
        saveTask = Task {
            defer { saving = false }
            if let result = await favorites.save(candidate, label: capturedLabel) {
                focused = false
                if result.omittedUnavailableCurrent {
                    savedOmittingCurrent = result.record
                } else {
                    controller.setLoadedFavoriteRecordID(result.record.id)
                    onDismiss()
                }
            }
        }
    }
}

struct GoFlyFavoriteRouteLabelEditor: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @Environment(\.colorScheme) private var colorScheme
    let record: FavoriteRouteRecord
    var onDismiss: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var label: String
    @State private var fallbackLabel = FavoriteLabelDefaults.defaultName()
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    init(record: FavoriteRouteRecord, onDismiss: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.record = record
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _label = State(initialValue: record.label ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GoFlyFavoriteRouteFailureNotice()

                    if saving {
                        ProgressView(goFlyString("favoriteRoutes.saving"))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(goFlyString("favoriteRoutes.label"), text: $label,
                                      prompt: Text(goFlyString("favoriteRoutes.namePlaceholder")))
                                .focused($focused)
                                .submitLabel(.done)
                                .onSubmit { focused = false }
                                .disabled(saving)
                                .accessibilityIdentifier("favoriteRoutes.editor.label")
                            Button { label = "" } label: {
                                GoFlyIcon(.close)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .disabled(label.isEmpty)
                            .accessibilityLabel(goFlyString("search.clear"))
                            .accessibilityIdentifier("favoriteRoutes.editor.clearLabel")
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .goFlySearchField(isFocused: focused)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(goFlyFavoriteRouteEndpoints(record))
                            .goFlyFont(GoFlyFont.subheadlineEmphasis)
                            .foregroundStyle(GoFlyTextColor.primary)
                        Text(goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
                            ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count))
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? GoFlyStyle.locationCardSurface : GoFlyStyle.canvas,
                                    in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("favoriteRoutes.editor.source")

                    Button {
                        guard !saving, favorites.canMutate else { return }
                        let capturedLabel = FavoriteLabelDefaults.resolved(label, fallback: fallbackLabel)
                        saving = true
                        saveTask = Task {
                            defer { saving = false }
                            if await favorites.updateLabel(record.id, label: capturedLabel) { onDismiss() }
                        }
                    } label: {
                        Text(goFlyString("favoriteRoutes.save"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoFlyButtonStyle(variant: .primary))
                    .disabled(saving || !favorites.canMutate || !favorites.records.contains(where: { $0.id == record.id }))
                    .padding(.top, 24)
                    .accessibilityIdentifier("favoriteRoutes.editor.save")
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, GoFlyStyle.favoriteEditorSaveBottomSpacing)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("favoriteRoutes.editor.content")
        }
        .presentationDetents([.height(max(200, headerHeight + contentHeight)), .large])
        .presentationDragIndicator(.visible)
        // Same opaque sheet as the place editor: a view background over the system
        // sheet material lets the Save button tint change with the detent.
        .presentationBackground(GoFlyStyle.surface)
        .interactiveDismissDisabled(saving)
        .onDisappear { saveTask?.cancel() }
    }

    private var header: some View {
        GoFlySheetHeader(title: nil) {
            Button(goFlyString("favoriteRoutes.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.editor.cancel")
        } trailing: {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Text(goFlyString("favoriteRoutes.deleteSingle"))
                        .foregroundStyle(GoFlyTextColor.danger)
                }
                .buttonStyle(.plain)
                .disabled(saving || !favorites.canMutate)
                .accessibilityIdentifier("favoriteRoutes.editor.delete")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
