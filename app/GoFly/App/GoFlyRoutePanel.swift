import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @EnvironmentObject private var favoriteRoutes: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    @Binding var showingFavoriteRoutes: Bool
    @Binding var showingImportedRoutes: Bool
    @Binding var showingAllPoints: Bool
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    /// The home-indicator inset the host adds below an execution panel.
    var bottomSafeInset: CGFloat = 0
    var onInspectRoute: () -> Void = { }
    /// Ending asks the owner to cancel the active route and return to planning.
    var onRequestEnd: () -> Void = { }
    var onSettings: () -> Void = { }
    /// A localization key for a floating error toast owned by the map screen.
    var onNotice: (String) -> Void = { _ in }
    /// 重試 on an interrupted route: repair the connection, then the route continues.
    var onRetryInterrupted: () -> Void = { }
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    var currentLocationAvailable: Bool? = nil
    var currentRouteOrigin: @MainActor () -> GeoCoordinate? = { nil }
    var isNarrow: Bool = false
    var onExpand: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var listContentHeight: CGFloat = 120
    @State private var showingDetails = false
    /// A quick plan finishes before a sheet is worth showing; failures show at once.
    @State private var startCardVisible = false
    @State private var startCardDelay: Task<Void, Never>?
    @State private var showingSaveFavorite = false
    @State private var editingFavorite: FavoriteRouteRecord?
    @State private var preparingFavoriteSave = false
    @ScaledMetric(relativeTo: .footnote) private var addFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var listIconSize: CGFloat = 20

    var body: some View {
        Group {
            if isNarrow && controller.phase == .editing {
                narrowView
            } else if controller.phase == .editing {
                editingView
            } else {
                executionPanel
            }
        }
        .accessibilityHidden(showingDetails || showingImportedRoutes || showingAllPoints || showingFavoriteRoutes || showingSaveFavorite)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel")
        .goFlyTracksSystemPresentation(showingDetails
            || showingSaveFavorite || editingFavorite != nil || controller.repairState != nil
            || showsStartCard,
            id: "route.panel.presentation")
        .sheet(isPresented: Binding(
            get: { showsStartCard },
            set: { if !$0 { controller.cancelStartPlanning() } }
        )) {
            if let state = controller.startPlanning {
                GoFlyRouteStartSheet(
                    state: state,
                    onCancel: { controller.cancelStartPlanning() },
                    onDeleteFailed: { _ = controller.deleteFailedStartPlacesAndStart() },
                    onClear: { _ = controller.clearAfterStartFailure() }
                )
            }
        }
        .onChange(of: controller.startPlanning) { _, state in updateStartCardVisibility(state) }
        .sheet(isPresented: Binding(
            get: { controller.repairState != nil },
            set: { if !$0 { controller.cancelPlanningRepair() } }
        )) {
            if let state = controller.repairState {
                GoFlyRouteRepairSheet(
                    state: state,
                    onCancel: { controller.cancelPlanningRepair() },
                    onDone: { _ = controller.confirmPlanningRepair() },
                    onDeleteFailed: { _ = controller.deleteFailedPlanningPlaces() }
                )
            }
        }
        .sheet(isPresented: $showingDetails) {
            GoFlySpeedSheet(
                speed: controller.draft.speed,
                canEdit: controller.canSetSpeed,
                onSpeedChanged: { _ = controller.setSpeed($0) },
                onDismiss: { showingDetails = false }
            )
        }
        .sheet(isPresented: $showingSaveFavorite) {
            GoFlySaveFavoriteRouteView(controller: controller, currentLocationAvailable: currentLocationAvailable,
                                      currentRouteOrigin: currentRouteOrigin) { showingSaveFavorite = false }
        }
        .sheet(item: $editingFavorite) { record in
            GoFlyFavoriteRouteLabelEditor(record: record, onDismiss: { editingFavorite = nil }) {
                editingFavorite = nil
                Task {
                    await favoriteRoutes.delete(record.id)
                    if controller.loadedFavoriteRecordID == record.id { controller.setLoadedFavoriteRecordID(nil) }
                }
            }
        }
        .onChange(of: controller.canEdit) { _, canEdit in
            if !canEdit {
                editingFavorite = nil
                showingDetails = false
                showingImportedRoutes = false
                showingAllPoints = false
                showingFavoriteRoutes = false
                showingSaveFavorite = false
            }
        }
    }

    /// Figma D1/D2: header 12 pt below the sheet top, list card, add / inspect row,
    /// star + Start row, 35 pt above the tab bar. Only the list scrolls (D2: up to 4 rows).
    private var editingView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                editingHeader
                    .padding(.bottom, 12)
                if let imported = controller.draft.gpxSource {
                    importedContent(imported)
                } else {
                    routeListCard(using: proxy)
                    routeActionRow(using: proxy)
                        .padding(.top, 4)
                }
                startControl
                    .padding(.top, 16)
            }
            .padding(.horizontal, controller.draft.gpxSource == nil ? 20 : 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route.panel.content")
        }
    }

    private var showsStartCard: Bool {
        guard let state = controller.startPlanning else { return false }
        switch state {
        case .partial, .allFailed: return true
        case .planning, .succeeded: return startCardVisible
        }
    }

    private func updateStartCardVisibility(_ state: RouteStartPlanningState?) {
        switch state {
        case .none:
            startCardDelay?.cancel(); startCardVisible = false
        case .planning:
            guard !startCardVisible, startCardDelay == nil else { return }
            startCardDelay = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, case .planning = controller.startPlanning else { startCardDelay = nil; return }
                startCardVisible = true; startCardDelay = nil
            }
        case .some:
            break
        }
    }

    private var isRouteUsable: Bool {
        controller.canStart &&
        (currentLocationAvailable != false || !controller.draft.nodes.contains(where: { $0.value == .current }))
    }

    private var startControl: some View {
        HStack(spacing: 12) {
            if controller.draft.gpxSource != nil {
                // D15: an imported GPX route has no favorite star; Cancel clears it.
                // `Button / Text · Neutral` Large, 120 × 56 like Start's height.
                GoFlyButton(title: goFlyString("common.cancel"), variant: .neutral) { _ = controller.clearImportedRoute() }
                    .frame(width: 120)
                    .accessibilityIdentifier("route.clearImported")
            } else {
                favoriteStarButton
            }
            if controller.error == .planningFailed, controller.canEdit {
                // D8: a failed plan turns the primary action into 修正.
                Button { _ = controller.fixPlanningOrder() } label: {
                    Text(goFlyString("route.repair.fixShort")).frame(maxWidth: .infinity)
                }
                .buttonStyle(GoFlyButtonStyle(variant: .primary))
                .goFlySteadyDisabled(controller.isFixingPlanningOrder)
                .accessibilityIdentifier("route.fix")
            } else {
                GoFlyButton(title: goFlyString("route.startShort"), icon: GoFlySymbols.play) { _ = controller.start() }
                    .goFlySteadyDisabled(!isRouteUsable)
                    .accessibilityIdentifier("route.start")
            }
        }
    }

    private var favoriteStarButton: some View {
        Button {
            if let matching = matchingFavoriteRecord {
                editingFavorite = matching
            } else {
                if let key = GoFlySaveFavoriteRouteView.eligibilityError(
                    draft: controller.draft, currentLocationAvailable: currentLocationAvailable) {
                    onNotice(key)
                } else {
                    presentFavoriteSaveSheet()
                }
            }
        } label: {
            Group {
                if preparingFavoriteSave {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    GoFlyStarIcon(size: 28, filled: isFavorite)
                }
            }
            .goFlyIconButtonChrome(
                diameter: 56,
                borderColorOverride: colorScheme == .dark ? GoFlyThemeColor.lineSeparator : GoFlyThemeColor.lineBorder
            )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(preparingFavoriteSave)
        .accessibilityLabel(goFlyString(preparingFavoriteSave ? "favoriteRoutes.loading" : (isFavorite ? "favoriteRoutes.editLabel" : "favoriteRoutes.add")))
        .accessibilityIdentifier("route.favorite.toggle")
    }

    private func presentFavoriteSaveSheet() {
        guard !preparingFavoriteSave else { return }
        preparingFavoriteSave = true
        Task {
            await favoriteRoutes.load()
            preparingFavoriteSave = false
            guard controller.canEdit else { return }
            if let key = GoFlySaveFavoriteRouteView.eligibilityError(
                draft: controller.draft, currentLocationAvailable: currentLocationAvailable) {
                onNotice(key)
                return
            }
            guard favoriteRoutes.canMutate else {
                onNotice(favoriteRoutes.error?.localizationKey ?? "favoriteRoutes.error.busy")
                return
            }
            showingSaveFavorite = true
        }
    }

    private var matchingFavoriteRecord: FavoriteRouteRecord? {
        if let id = controller.loadedFavoriteRecordID,
           let record = favoriteRoutes.records.first(where: { $0.id == id }) {
            return record
        }
        if let gpx = controller.draft.gpxSource {
            return favoriteRoutes.records.first { record in
                record.sourceKind == .gpx &&
                record.displayFilename == gpx.displayFilename &&
                record.count == gpx.document.pointCount
            }
        } else if controller.draft.nodes.count >= 2 {
            let places = controller.draft.nodes.compactMap { node -> MapPlace? in
                if case .place(let p) = node.value { return p } else { return nil }
            }
            if places.count == controller.draft.nodes.count,
               let first = places.first, let last = places.last {
                return favoriteRoutes.records.first { record in
                    record.sourceKind == .manual &&
                    record.count == places.count &&
                    record.start == first.coordinate &&
                    record.end == last.coordinate
                }
            }
        }
        return nil
    }

    private var isFavorite: Bool {
        matchingFavoriteRecord != nil
    }

    private var executionPanel: some View {
        VStack(spacing: 16) {
            if [.planning, .preparing, .pausing, .cancelling].contains(controller.phase) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(goFlyString("route.phase.\(controller.phase.rawValue)"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            } else if controller.phase == .unknown {
                HStack(spacing: 12) {
                    settingsButton
                    cancelButton
                }
                .padding(.bottom, 16)
            } else {
                GoFlyRouteRunningControls(
                    title: controller.roundTripEnabled ? goFlyLocalizedFormat(goFlyString("route.autoRoundTrip"),
                        goFlyString(controller.heading == .reverse ? "route.direction.reverse" : "route.direction.forward"))
                        : GoFlyRouteRunningControls.remainingTitle(controller.progress?.estimatedRemaining),
                    fraction: controller.progress?.fraction ?? 0,
                    isRoundTrip: controller.roundTripEnabled,
                    isReversed: controller.heading == .reverse,
                    speed: controller.draft.speed.kilometersPerHour,
                    canToggleRoundTrip: controller.canSetRoundTrip,
                    canToggleDirection: controller.canToggleHeading,
                    canChangeSpeed: controller.canSetSpeed,
                    isPaused: [.paused, .interrupted].contains(controller.phase),
                    isInterrupted: controller.phase == .interrupted,
                    canPlayback: controller.phase == .interrupted ? true : (controller.phase == .paused ? controller.canResume : controller.canPause),
                    canEnd: controller.canCancel,
                    onToggleRoundTrip: { _ = controller.setRoundTripEnabled(!controller.roundTripEnabled) },
                    onToggleDirection: { _ = controller.toggleHeading() },
                    onSpeedTap: { showingDetails = true },
                    onPlayback: {
                        if controller.phase == .interrupted { onRetryInterrupted() }
                        else if controller.phase == .paused { _ = controller.resume() } else { _ = controller.pause() }
                    },
                    onEnd: onRequestEnd
                )
            }
        }
        .padding(.horizontal, 20)
        // The label row starts 20 pt below the grabber; the safe area supplies the bottom 34 pt.
        .padding(.top, GoFlyGrabber.rowHeight)
        // D6 / D10.a: 40 pt from the primary button row to the panel bottom, inset included.
        .padding(.bottom, max(0, GoFlyStyle.sheetButtonBottomSpacing - bottomSafeInset))
        .frame(maxWidth: .infinity)
        .background(GoFlyStyle.cardSurface)
        .overlay(alignment: .top) {
            Capsule().fill(GoFlyStyle.border).frame(width: 36, height: GoFlyGrabber.capsuleHeight).padding(.top, GoFlyGrabber.topInset)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel.content")
    }

    private var narrowView: some View {
        HStack(spacing: 8) {
            Button(action: { onExpand?() }) {
                Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                    .goFlyFont(GoFlyFont.title)
                    .lineLimit(1)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route.heading")

            Spacer(minLength: 8)

            headerButton(identifier: "route.favoriteRoutes",
                         label: goFlyString("favoriteRoutes.title"), enabled: controller.canEdit) {
                showingFavoriteRoutes = true
            } icon: { GoFlyStarIcon(size: 18, filled: false) }

            headerButton(identifier: "route.importedRoutes",
                         label: goFlyString("imports.title"), enabled: controller.canEdit) {
                showingImportedRoutes = true
            } icon: { GoFlyRouteFolderIcon(size: 20) }
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .background(GoFlyStyle.cardSurface)
        .contentShape(Rectangle())
        .onTapGesture { onExpand?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel.narrow")
    }

    private var editingHeader: some View {
        HStack(spacing: 8) {
            Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                .goFlyFont(GoFlyFont.title)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(controller.draft.gpxSource == nil ? "route.heading" : "route.importedSummary")
            Spacer(minLength: 8)
            headerButton(identifier: "route.favoriteRoutes",
                         label: goFlyString("favoriteRoutes.title"), enabled: controller.canEdit) {
                showingFavoriteRoutes = true
            } icon: { GoFlyStarIcon(size: 18, filled: false) }
            headerButton(identifier: "route.importedRoutes",
                         label: goFlyString("imports.title"), enabled: controller.canEdit) {
                showingImportedRoutes = true
            } icon: { GoFlyRouteFolderIcon(size: 20) }
        }
        .padding(.trailing, 4)
    }

    private func importedContent(_ imported: GPXRouteSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GoFlyGPXPointList(points: imported.document.segments.flatMap { $0 }, summarized: true,
                               onFocus: onFocusPoint, onShowAll: { showingAllPoints = true })
        }
    }

    /// Rows are 60 pt; the list scrolls once the panel reaches its 414 pt maximum.
    private static let maxPanelContent: CGFloat = 388
    private static let rowHeight: CGFloat = 60
    /// Everything in the editing panel except the list: header, gaps, action row, Start row and bottom inset.
    private static let panelChrome: CGFloat = 192

    private var listHeight: CGFloat {
        // D2: the sheet tops out at 416 pt above the tab bar (404 pt under the 12 pt grabber); only the list scrolls.
        let cap = min(Self.maxPanelContent - Self.panelChrome, max(Self.rowHeight, maximumHeight - Self.panelChrome))
        return min(listContentHeight, cap)
    }

    private func routeListCard(using proxy: ScrollViewProxy) -> some View {
        GoFlyRouteNodeCard(controller: controller, proxy: proxy, height: listHeight,
                           lightSurface: GoFlyStyle.canvas,
                           onEditNode: onEditNode,
                           onContentHeightChange: { listContentHeight = $0 })
            .accessibilityIdentifier("route.nodes.card")
    }

    private func routeActionRow(using proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 16) {
            Button { addWaypoint(using: proxy) } label: {
                HStack(spacing: 6) {
                    Text("＋")
                    Text(goFlyString("route.addStop"))
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .ghostPrimary, size: .inline, expandsToFill: false))
            .disabled(!controller.canAddNode)
            .accessibilityIdentifier("route.addNode")
            .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount ? goFlyString("route.nodeLimit") : "")
            Spacer(minLength: 0)
            Button(action: onInspectRoute) {
                Label {
                    Text(goFlyString("route.viewList"))
                } icon: {
                    GoFlyIcon(GoFlySymbols.routeList, size: listIconSize, maximumSize: 28)
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .ghostSecondary, size: .inline, expandsToFill: false))
            .disabled(!controller.canEdit)
            .accessibilityIdentifier("route.viewList")
        }
    }

    private func addWaypoint(using proxy: ScrollViewProxy) {
        let existingIDs = Set(controller.draft.nodes.map(\.id))
        guard controller.addEmptyWaypoint(),
              let newID = controller.draft.nodes.first(where: { !existingIDs.contains($0.id) })?.id else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newID, anchor: .bottom) }
        }
    }

    private func headerButton<Icon: View>(identifier: String, label: String,
                              enabled: Bool, action: @escaping () -> Void,
                              @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .goFlyIconButtonChrome(diameter: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var cancelButton: some View {
        Button(action: onRequestEnd) {
            GoFlyIconLabel(title: goFlyString("execution.end"), icon: GoFlySymbols.close)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .neutral))
        .frame(width: 120)
        .disabled(!controller.canCancel)
        .accessibilityIdentifier("route.cancel")
    }

    private var settingsButton: some View {
        Button(goFlyString("operation.settings"), action: onSettings)
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .accessibilityIdentifier("route.settings")
    }



}

private struct GoFlyRoundTripControl: View {
    @ObservedObject var controller: RouteExecutionController

    var body: some View {
        Button {
            _ = controller.setRoundTripEnabled(!controller.roundTripEnabled)
        } label: {
            HStack(spacing: 8) {
                GoFlyRoundTripIcon(enabled: controller.roundTripEnabled, size: 14)
                Text(goFlyString("route.roundTripShort"))
                    .goFlyFont(GoFlyFont.footnoteEmphasis)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(controller.roundTripEnabled ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
            .overlay { if !controller.roundTripEnabled { Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 0.75) } }
            .contentShape(Capsule())
            .foregroundStyle(!controller.canSetRoundTrip ? GoFlyTextColor.disabled
                             : (controller.roundTripEnabled ? GoFlyTextColor.inverse : GoFlyStyle.primary))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(!controller.canSetRoundTrip)
        .accessibilityValue(controller.roundTripEnabled ? "1" : "0")
        .accessibilityHint(goFlyString("route.roundTripHint"))
        .accessibilityIdentifier("route.roundTrip")
    }
}
