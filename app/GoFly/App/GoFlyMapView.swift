import Combine
import GoFlyCore
import GoFlyTransport
import MapKit
import SwiftUI
import UIKit

/// One App-owned assembly, created before SwiftUI attaches its observers.
/// View reconstruction reuses these exact domain owners and cannot fence live work.
struct GoFlyMovementPresentation: Equatable {
    var status: GoFlySessionStatus = .started
    var marker: PositionMarker?
    var errorKeys: [String] = []
    var route: PlannedRoute?
    var routeDistance: Double?
}

@MainActor
final class GoFlyMovementModel: ObservableObject {
    @Published private(set) var presentation = GoFlyMovementPresentation()
    private var presentationUpdateQueued = false
    private var dataErrorKeys: @MainActor () -> [String] = { [] }
    @Published private(set) var presentationMode: SessionMapMode
    let route: RouteExecutionController
    let joystick: JoystickMovementController
    let recovery: ConnectionRecoveryController
    let continuation: MovementContinuationController
    let positionHold: PositionHoldController
    /// Owned here so the joystick's range closure never outlives or loses its controller
    /// when the map view struct is rebuilt.
    let wanderRange: WanderRangeController
    let keepAlive: PositionKeepAlive
    let placeSearch: any PlaceSearching
    let placeResolver: any PlaceResolving
    /// Owned here so the map view uses it without observing every fix.
    let location: GoFlyRealLocation
    private let service: ServiceController
    private var subscriptions: [AnyCancellable] = []
    private var speedSynchronizer: MovementSpeedSynchronizer?
    private var mapAdmission: (@MainActor () -> Bool)?

    init(service: ServiceController, recoveryStore: SessionRecoveryStore) {
        self.service = service
#if DEBUG && targetEnvironment(simulator)
        location = GoFlyUITestOverrides.isFrameMode
            ? GoFlyRealLocation(uiTestFixture: true)
            : GoFlyRealLocation()
#else
        location = GoFlyRealLocation()
#endif
        let placeSearch: any PlaceSearching
        let placeResolver: any PlaceResolving
#if DEBUG && targetEnvironment(simulator)
        if GoFlyUITestOverrides.isFrameMode {
            placeSearch = GoFlyUITestPlaceSearch()
            placeResolver = GoFlyUITestPlaceResolver()
        } else {
            placeSearch = MapKitPlaceSearch()
            placeResolver = MapKitPlaceResolver()
        }
#else
        placeSearch = MapKitPlaceSearch()
        placeResolver = MapKitPlaceResolver()
#endif
        self.placeSearch = placeSearch
        self.placeResolver = placeResolver
        let snapshot = recoveryStore.initialSnapshot
#if DEBUG && targetEnvironment(simulator)
        presentationMode = GoFlyUITestOverrides.initialMode(for: GoFlyUITestOverrides.frame) ?? snapshot.mode
#else
        presentationMode = snapshot.mode
#endif
        route = RouteExecutionController(
            draft: Self.routeDraft(restoring: snapshot.draft), planner: Self.routePlanner(),
            commands: service, search: placeSearch
        )
        _ = route.setRoundTripEnabled(snapshot.roundTripEnabled)
        joystick = JoystickMovementController(commands: service, speed: GoFlyPreferences.shared.movementSpeed)
        positionHold = PositionHoldController(service: service)
        let preferences = GoFlyPreferences.shared
        let rangeController = WanderRangeController(
            radius: preferences.wanderRadius, isVisible: preferences.wanderRangeVisible,
            onChange: { GoFlyPreferences.shared.setWanderRange(radius: $0, isVisible: $1) })
        wanderRange = rangeController
        joystick.wanderRange = { rangeController.range(origin: $0) }
        joystick.wanderStarting = { rangeController.wanderStarting(at: $0) }
        keepAlive = PositionKeepAlive(service: service)
#if DEBUG && targetEnvironment(simulator)
        let recoveryProbe: any TunnelProbing = GoFlyUITestOverrides.isFrameMode
            ? GoFlyUITestOverrides.fixtureTunnelProbe(for: GoFlyUITestOverrides.frame)
            : NetworkTunnelProbe()
#else
        let recoveryProbe: any TunnelProbing = NetworkTunnelProbe()
#endif
        recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick,
            probe: recoveryProbe, positionHold: positionHold, retainedColdSnapshot: snapshot
        )
        let routeForPresentation = route
#if DEBUG && targetEnvironment(simulator)
        let continuedProcessingDriver: any ContinuedProcessingDriving = GoFlyUITestOverrides.isFrameMode
            ? GoFlyUITestContinuedProcessingDriver()
            : GoFlyContinuedProcessingDriver.shared
#else
        let continuedProcessingDriver: any ContinuedProcessingDriving = GoFlyContinuedProcessingDriver.shared
#endif
        continuation = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery, positionHold: positionHold,
            driver: continuedProcessingDriver,
            presentation: { kind, progress in
                if kind != .finiteRoute {
                    let percent = min(100, max(0, Int(progress.cumulativeAcknowledgedDurationSeconds / BackgroundRunDuration.shared.seconds * 100)))
                    return (title: goFlyString("background.activity.\(kind.rawValue)"),
                            subtitle: goFlyLocalizedFormat(goFlyString("background.activity.durationProgress"), percent))
                }
                let percent = min(100, max(0, Int((routeForPresentation.progress?.fraction ?? 0) * 100)))
                return (title: goFlyString("background.activity.\(kind.rawValue)"),
                 subtitle: goFlyLocalizedFormat(
                    goFlyString("background.activity.routeProgress"), percent))
            }
        )
        speedSynchronizer = MovementSpeedSynchronizer(
            route: route, joystick: joystick, initial: GoFlyPreferences.shared.movementSpeed,
            onChange: { GoFlyPreferences.shared.setMovementSpeed($0) })
        // Both screens observe this owner and read the same status projection.
        subscriptions = [service.objectWillChange, recovery.objectWillChange,
                         route.objectWillChange, joystick.objectWillChange,
                         positionHold.objectWillChange, continuation.objectWillChange,
                         recoveryStore.objectWillChange].map { publisher in
            publisher.sink { [weak self] _ in self?.queuePresentationUpdate() }
        }
    }

    var status: GoFlySessionStatus { presentation.status }
    var activeMovement: ActiveMovement? {
        ActiveMovement(route: route, joystick: joystick, positionHold: positionHold)
    }

    private func queuePresentationUpdate() {
        guard !presentationUpdateQueued else { return }
        presentationUpdateQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.presentationUpdateQueued = false
            let active = self.activeMovement
            let running = active?.isRunning == true
            let paused = active?.isPaused == true
            // A silent automatic repair shows the connecting pill, not an error;
            // only its failure becomes one.
            let silentRepair = self.recovery.isSilentRepairInProgress
            let errors = SessionStatusErrors(connection: silentRepair ? .checking : self.recovery.connectionState,
                service: silentRepair ? nil : self.service.error, route: self.route.error, joystick: self.joystick.error,
                wander: self.joystick.wanderError,
                dataErrors: self.dataErrorKeys())
            let hasError = !errors.isEmpty
            let connecting = self.service.movementConnection != .available
            let next = GoFlyMovementPresentation(
                status: GoFlySessionStatus(hasError: hasError, connecting: connecting, running: running, paused: paused,
                    hasSimulated: self.service.hasSimulated),
                marker: self.service.displayPositionMarker, errorKeys: errors.keys,
                route: self.route.intent?.route,
                routeDistance: self.route.progress?.committedDistanceMeters)
            if self.presentation != next { self.presentation = next }
        }
    }

    func observeDataErrors(recoveryStore: SessionRecoveryStore, favorites: FavoritePlacesStore,
                           importedRoutes: ImportedRoutesStore, favoriteRoutes: FavoriteRoutesStore) {
        dataErrorKeys = {
            var keys = [recoveryStore.error?.localizationKey, favorites.error?.rawValue,
                        importedRoutes.error?.localizationKey, favoriteRoutes.error?.localizationKey].compactMap { $0 }
            if case .blocked(let failure) = recoveryStore.loadState { keys.append(failure.localizationKey) }
            if case .blocked(let failure) = favorites.loadState { keys.append(failure.rawValue) }
            if case .blocked(let failure) = importedRoutes.loadState { keys.append(failure.localizationKey) }
            if case .blocked(let failure) = favoriteRoutes.loadState { keys.append(failure.localizationKey) }
            return keys
        }
        subscriptions += [favorites.objectWillChange, importedRoutes.objectWillChange,
                          favoriteRoutes.objectWillChange].map { publisher in
            publisher.sink { [weak self] _ in self?.queuePresentationUpdate() }
        }
        queuePresentationUpdate()
    }

    func setPresentationMode(_ mode: SessionMapMode) {
        guard route.canEdit else { return }
        presentationMode = mode
    }

    func attachMapAdmission(_ admission: @escaping @MainActor () -> Bool) {
        mapAdmission = admission
    }

    func detachMapAdmission() { mapAdmission = nil }

    var canExportFromMap: Bool {
        guard mapAdmission?() == true, UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController else { return false }
        // Read the actual presentation tree, including sheets and importers
        // owned by child views. Export must not dismiss an unfinished editor.
        var pending = [root]
        var visited = 0
        while let controller = pending.popLast() {
            visited += 1
            guard visited <= 128, controller.presentedViewController == nil else { return false }
            pending.append(contentsOf: controller.children)
        }
        return true
    }

    private static func routeDraft(restoring saved: RouteDraft) -> RouteDraft {
#if DEBUG && targetEnvironment(simulator)
        if let draft = GoFlyUITestOverrides.routeDraft(for: GoFlyUITestOverrides.frame) { return draft }
#endif
        return saved
    }

    private static func routePlanner() -> any RoutePlanning {
#if DEBUG && targetEnvironment(simulator)
        if GoFlyUITestOverrides.isFrameMode {
            return GoFlyUITestRoutePlanner(outcome: GoFlyUITestOverrides.routePlanOutcome)
        }
#endif
        return FallbackRoutePlanner(provider: MapKitRoutePathProvider())
    }

}

struct GoFlyMapView: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @ObservedObject private var movement: GoFlyMovementModel
    @ObservedObject var service: ServiceController
    let recoveryStore: SessionRecoveryStore
    let setupMetadata: GoFlySetupMetadata?
    private let initialSheetDetent: GoFlySheetDetent?
    @ObservedObject private var route: RouteExecutionController
    @ObservedObject private var joystick: JoystickMovementController
    @ObservedObject private var recovery: ConnectionRecoveryController
    @ObservedObject private var continuation: MovementContinuationController
    @ObservedObject private var positionHold: PositionHoldController
    private let uiTestFixtureFrame: String?
    private var mode: GoFlyMapMode {
        get { movement.presentationMode }
        nonmutating set { movement.setPresentationMode(newValue) }
    }
    @StateObject private var checkpoints: SessionCheckpointSaver
    private var location: GoFlyRealLocation { movement.location }
    @StateObject private var search: CandidateController
    @StateObject private var wanderSearch: CandidateController
    @State private var cameraIntent: GoFlyCameraIntent?
    private let mapPlaces: any PlaceResolving
    @State private var pendingGPSRecenter = false
    @State private var projection: GoFlyMapProjection?
    @State private var topFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @State private var teleportCardFrame = CGRect.zero
    @State private var bottomCardFrame = CGRect.zero
    @State private var bottomContentHeight: CGFloat = 260
    @State private var sheetDetent: GoFlySheetDetent = .expanded
    @State private var didApplyInitialSheetDetent = false
    @State private var sheetHeight: CGFloat = 320
    @State private var presentedSheet: GoFlyMapSheet?
    @State private var searchFocusRequest: UUID?
    @State private var pendingRouteNodeTapID: RouteNodeID?
    @State private var showingSearch = false
    @State private var showingRouteList = false
    @State private var searchFavorites = false
    @State private var showingFavoriteRoutes = false
    @State private var showingImportedRoutes = false
    @State private var showingAllImportedPoints = false
    @State private var recentPlaces: [MapPlace] = []
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var searchPasteWarning: GoFlySearchPasteWarning?
    @State private var searchPasteConfirmationTask: Task<Void, Never>?
    @State private var bottomBarHeight: CGFloat = 83
    @State private var candidateHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var goWidth: CGFloat = 68
    @State private var showingSettings = false
    @State private var notices = NoticeState()
    /// False while the scene is leaving or returning: the iOS app snapshot and
    /// the first frames back must not show a paused-state toast that the
    /// returning scene is about to resolve.
    @State private var sceneSettled = true
    @State private var sceneSettleTask: Task<Void, Never>?
    @State private var isMapPicking = false
    @StateObject private var joystickOrigin: JoystickOriginController
    @StateObject private var wander: WanderPlanningCoordinator
    @ObservedObject private var wanderRange: WanderRangeController
    @State private var selectedWanderPlace: MapPlace? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    /// Planning hosts outlive the body copy they were attached from; an
    /// environment value captured there would stay at its onAppear phase.
    @State private var sceneActivity = GoFlySceneActivity()

    init(
        service: ServiceController,
        recoveryStore: SessionRecoveryStore,
        movement: GoFlyMovementModel,
        setupMetadata: GoFlySetupMetadata? = nil,
        uiTestFixtureFrame: String? = nil,
        initialSheetDetent: GoFlySheetDetent? = nil
    ) {
        self.movement = movement
        _service = ObservedObject(wrappedValue: service)
        self.recoveryStore = recoveryStore
        self.setupMetadata = setupMetadata
        self.uiTestFixtureFrame = uiTestFixtureFrame
        self.initialSheetDetent = initialSheetDetent
        _route = ObservedObject(wrappedValue: movement.route)
        _joystick = ObservedObject(wrappedValue: movement.joystick)
        _recovery = ObservedObject(wrappedValue: movement.recovery)
        _continuation = ObservedObject(wrappedValue: movement.continuation)
        _positionHold = ObservedObject(wrappedValue: movement.positionHold)
        _search = StateObject(wrappedValue: CandidateController(search: movement.placeSearch))
        _wanderSearch = StateObject(wrappedValue: CandidateController(search: movement.placeSearch))
        mapPlaces = movement.placeResolver
        let origin = JoystickOriginController(service: service, joystick: movement.joystick)
        _joystickOrigin = StateObject(wrappedValue: origin)
        let wanderCoordinator = WanderPlanningCoordinator(
            service: service, joystick: movement.joystick, origin: origin,
            planSegment: { [route = movement.route] in try await route.planWanderSegment(from: $0, to: $1) })
        _wander = StateObject(wrappedValue: wanderCoordinator)
        _wanderRange = ObservedObject(wrappedValue: movement.wanderRange)
        _checkpoints = StateObject(wrappedValue: SessionCheckpointSaver(
            store: recoveryStore, backgroundTasks: UIKitBackgroundSaveTasks()))
    }

    private var isWanderMap: Bool { mode == .joystick && joystick.wanderEnabled && route.picker == nil }
    private var activeSearch: CandidateController {
        route.picker?.candidates ?? (isWanderMap ? wanderSearch : search)
    }
    private var activeCandidate: TeleportCandidate? {
        if let picker = route.picker { return picker.candidates.candidate }
        if isWanderMap { return wanderSearch.candidate }
        // Teleport goes to the Pin; the route tab confirms it into the selected field (D4).
        return (mode == .teleport || mode == .route || mode == .joystick) && route.canEdit ? search.candidate : nil
    }
    private var canSwitchMode: Bool { route.canEdit && route.picker == nil && !showsOperationPanel }
    private var canRequestWanderStart: Bool { wander.canRequestStart }
    private var isWanderReplanning: Bool { wander.isReplanning }

    private var viewportGap: CGFloat { dynamicTypeSize.isAccessibilitySize ? 4 : 8 }
    private var bottomPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 12 }

    private func updateMeasuredHeight(_ height: CGFloat, from current: CGFloat, assign: (CGFloat) -> Void) {
        guard abs(height - current) > 0.5 else { return }
        assign(height)
    }

    private func updateMeasuredFrame(_ frame: CGRect, from current: CGRect, assign: (CGRect) -> Void) {
        guard abs(frame.minX - current.minX) > 0.5
                || abs(frame.minY - current.minY) > 0.5
                || abs(frame.width - current.width) > 0.5
                || abs(frame.height - current.height) > 0.5 else { return }
        assign(frame)
    }

    var body: some View { mapNavigation }

    private var mapNavigation: some View {
        let root = NavigationStack {
            GeometryReader { geometry in
                mapContent(in: geometry)
                    .coordinateSpace(name: "mapRoot")
                    // An origin ACK can arrive while the position hold still prepares;
                    // the queued wander starts once native work drains.
                    .onChange(of: service.nativeBusy) { _, busy in
                        if !busy, wander.hasAcknowledgedPendingStart,
                           scenePhase == .active, !recovery.isChecking { wander.resumePending() }
                    }
                    // One Start press: the origin teleport's ACK can precede the moment the
                    // joystick owner may enable wander, so also resume when it becomes enabled.
                    .onChange(of: joystick.canSetWanderEnabled && joystick.canStartWanderPlanning) { _, ready in
                        if ready, wander.hasAcknowledgedPendingStart,
                           scenePhase == .active, !recovery.isChecking { wander.resumePending() }
                    }
                    .accessibilityHidden(presentedSheet != nil || showingSearch || showingImportedRoutes
                        || showingAllImportedPoints || route.picker != nil)
            }
            // Destinations must sit inside the stack; on the stack itself SwiftUI ignores them.
            .navigationDestination(isPresented: $showingSettings) {
                ServiceSettingsView(
                    service: service,
                    movement: movement,
                    continuation: continuation,
                    recovery: recovery,
                    setupMetadata: setupMetadata
                )
            }
            .navigationDestination(isPresented: $showingRouteList) {
                GoFlyRouteListView(
                    controller: route,
                    onEditNode: selectRouteNode,
                    onDismiss: { showingRouteList = false }
                )
                .navigationDestination(isPresented: routePickerNavigationBinding) {
                    searchScreen
                }
            }
            .navigationDestination(isPresented: $showingImportedRoutes) {
                GoFlyImportedRoutesView(controller: route, onLoaded: {
                    showingImportedRoutes = false
                }, onFocusPoint: { coordinate in
                    showingImportedRoutes = false
                    cameraIntent = GoFlyCameraIntent(coordinate: coordinate)
                })
            }
            .navigationDestination(isPresented: $showingAllImportedPoints) {
                if let source = route.draft.gpxSource {
                    GoFlyGPXPointsView(document: source.document, title: source.displayFilename, onFocus: { coordinate in
                        showingAllImportedPoints = false
                        cameraIntent = GoFlyCameraIntent(coordinate: coordinate)
                    })
                }
            }
            .modifier(GoFlyMapSheetsModifier(
                details: detailsCoverBinding, detailsView: { detailsView($0) },
                placesShown: favoritesShown, onDismissPlaces: { presentedSheet = nil }, places: { favoritesView },
                routesShown: showingFavoriteRoutes, onDismissRoutes: { showingFavoriteRoutes = false },
                routes: { GoFlyFavoriteRoutesView(controller: route) { showingFavoriteRoutes = false } }))
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyNativeBackTitle()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: showingRouteList) { _, isShowing in
            if !isShowing { pendingRouteNodeTapID = nil }
        }

        let lifecycle = observeMapLifecycle(root)
        let inputs = observeMapInputs(lifecycle)
        let sceneEvents = observeMapScene(inputs)
        let movementEvents = observeMapMovement(sceneEvents)
        return observeMapPresentation(movementEvents)
            .fullScreenCover(isPresented: Binding(
                get: { (showingSearch || (route.picker != nil && !showingRouteList)) && !isMapPicking },
                set: { shown in
                    if !shown {
                        showingSearch = false
                        if isMapPicking { isMapPicking = false }
                    }
                }
            )) { NavigationStack { searchScreen }.interactiveDismissDisabled() }
            .tint(GoFlyStyle.primary)
    }

    private func observeMapLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                sceneActivity.isActive = scenePhase == .active
#if DEBUG && targetEnvironment(simulator)
                if let uiTestFixtureFrame {
                    configureUITestFrame(uiTestFixtureFrame)
                }
#endif
                if !didApplyInitialSheetDetent {
                    didApplyInitialSheetDetent = true
                    if let initialSheetDetent { sheetDetent = initialSheetDetent }
                }
                joystickOrigin.attach(JoystickOriginHost(
                    isJoystickMode: { mode == .joystick },
                    isSceneActive: { sceneActivity.isActive },
                    requestLocationFix: { location.requestRecenter() },
                    mapCenter: { projection?.upperThirdCoordinate ?? projection?.centerCoordinate }))
                wander.attach(wanderPlanningHost)
                // Wired here, not in init: init also runs for view copies SwiftUI discards, and a
                // weak reference to such a copy's coordinator would die and let the origin ACK's
                // position hold wipe the wander start.
                movement.positionHold.suppressesHold = { [weak wander] in wander?.isStartOrigin($0) == true }
                movement.attachMapAdmission {
                    !showingSettings && !showingSearch && !showingRouteList && !showingImportedRoutes
                        && !showingAllImportedPoints && presentedSheet == nil && route.picker == nil
                }
                location.start()
                if cameraIntent == nil {
                    if mode == .route, let planned = route.plannedRoute {
                        cameraIntent = GoFlyCameraIntent(route: planned)
                    } else if let position = service.positionMarker {
                        cameraIntent = GoFlyCameraIntent(coordinate: position.coordinate)
                    }
                }
                if scenePhase == .active {
                    location.sceneDidBecomeActive()
                    continuation.sceneDidBecomeActive()
                    movement.keepAlive.sceneDidBecomeActive()
                }
#if DEBUG && targetEnvironment(simulator)
                // B11 captures the explicit connecting state without settling
                // the local probe before its screenshot is taken.
                if uiTestFixtureFrame != "B11" { recovery.requestForegroundCheck() }
#else
                recovery.requestForegroundCheck()
#endif
                service.warmupSession()
                if isTeleportHoldRecovery { sheetDetent = .collapsed }
                if dynamicTypeSize.isAccessibilitySize { sheetDetent = .expanded }
            }
            .onChange(of: dynamicTypeSize) { _, size in
                if size.isAccessibilitySize { sheetDetent = .expanded }
            }
            .onDisappear {
                cancelSearchPasteConfirmation()
                movement.detachMapAdmission()
                wander.cancelAll()
            }
    }

#if DEBUG && targetEnvironment(simulator)
    private func configureUITestFrame(_ frame: String) {
        let places = GoFlyUITestOverrides.fixturePlaces
        if let mode = GoFlyUITestOverrides.initialMode(for: frame) { movement.setPresentationMode(mode) }
        sheetDetent = frame == "B2" ? .half
            : (["B1", "B6", "B7", "B8", "B9", "B10", "B11", "D3", "E1.a", "E2.a"].contains(frame) ? .collapsed : .expanded)
        if let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) {
            cameraIntent = GoFlyCameraIntent(coordinate: coordinate, resetsZoom: true)
        }

        switch frame {
        case "B1":
            if let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) {
                let title = goFlyString("figma.fixture.b1.position")
                recordRecentPlace(MapPlace(id: .coordinate(coordinate), title: title, coordinate: coordinate))
            }
        case "B3":
            if let coordinate = GeoCoordinate(latitude: 24.200544, longitude: 121.348432) {
                recordRecentPlace(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                                           coordinate: coordinate))
            }
            recordRecentPlace(places[0])
            showingSearch = true
        case "B4":
            showingSearch = true
            search.updateQuery("台北")
        case "B2":
            Task { @MainActor in await startRunningPositionHoldUITestFixture() }
        case "B5":
            selectSearchPlace(places[2])
        case "B6":
            Task { @MainActor in
                await startRunningPositionHoldUITestFixture(target: places[0])
                snackbar = GoFlySnackbarMessage(text: goFlyLocalizedFormat(goFlyString("teleport.completed"), places[0].title))
            }
        case "B7":
            selectSearchPlace(places[2])
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                _ = service.teleport(to: TeleportCandidate(place: places[2]))
            }
        case "B8", "B9":
            Task { @MainActor in await startPausedPositionHoldUITestFixture(target: places[0]) }
        case "C1", "C2", "C3", "C4":
            presentedSheet = GoFlyMapSheet(content: .favorites)
        case "D5":
            recentPlaces = [places[0]]
            if let nodeID = route.draft.destination?.id { _ = route.openPicker(for: nodeID) }
        case "D4":
            search.select(places[2])
        case "D6", "D7":
            Task { @MainActor in await startRouteUITestFixture(interrupt: false) }
        case "D10":
            Task { @MainActor in await startRouteUITestFixture(interrupt: true) }
        case "D10.a":
            Task { @MainActor in await startRouteUITestFixture(interrupt: false, pauseForUser: true) }
        case "D19", "D20", "D21", "D22":
            showingFavoriteRoutes = true
        case "D23":
            showingRouteList = true
        case "E2", "E2.a":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                await startWanderUITestFixture(target: places[1], showLocationCard: false)
            }
        case "E4":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                await startWanderUITestFixture(target: places[1], showLocationCard: true)
            }
        case "E5":
            Task { @MainActor in
                await startWanderUITestFixture(target: places[1], showLocationCard: false)
                mode = .joystick
                for _ in 0..<1_000 {
                    if joystick.wanderEnabled && joystick.canPause { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                if joystick.wanderEnabled && joystick.canPause { joystick.continuationDidBecomeUnavailable() }
                for _ in 0..<1_000 {
                    if joystick.wanderEnabled && [.paused, .suspended, .interrupted].contains(joystick.phase) { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        case "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9":
            showingSettings = true
        default:
            break
        }
    }

    private func startPausedPositionHoldUITestFixture(target: MapPlace) async {
        for _ in 0..<1_000 {
            if !service.nativeBusy, !recovery.isChecking,
               service.movementConnection == .available,
               (service.phase == .ready || service.phase == .stopped) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !service.nativeBusy, service.movementConnection == .available,
              (service.phase == .ready || service.phase == .stopped),
              service.teleport(to: TeleportCandidate(place: target)) else { return }
        recordRecentPlace(target)
        for _ in 0..<1_000 {
            if positionHold.phase == .paused || continuation.noticeKey != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func startRunningPositionHoldUITestFixture(target requestedTarget: MapPlace? = nil) async {
        for _ in 0..<1_000 {
            if !service.nativeBusy, !recovery.isChecking,
               service.movementConnection == .available,
               (service.phase == .ready || service.phase == .stopped) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !service.nativeBusy, !recovery.isChecking,
              service.movementConnection == .available,
              (service.phase == .ready || service.phase == .stopped),
              let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) else { return }
        let target = requestedTarget ?? MapPlace(
            id: .coordinate(coordinate), title: goFlyString("figma.fixture.b2.position"), coordinate: coordinate)
        recordRecentPlace(target)
        guard service.teleport(to: TeleportCandidate(place: target)) else { return }
        for _ in 0..<1_000 {
            if positionHold.phase == .running { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func startRouteUITestFixture(interrupt: Bool, pauseForUser: Bool = false) async {
        for _ in 0..<1_000 {
            if !service.nativeBusy, !recovery.isChecking,
               service.movementConnection == .available,
               (service.phase == .ready || service.phase == .stopped) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !service.nativeBusy, service.movementConnection == .available,
              (service.phase == .ready || service.phase == .stopped), route.start() else { return }
        for _ in 0..<1_000 {
            if route.phase == .running { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        if interrupt, route.phase == .running {
            route.connectionDidBecomeUnavailable()
            for _ in 0..<1_000 {
                if route.phase == .paused || route.phase == .interrupted { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            // The D10 frame presents the recovered, ready-to-continue state;
            // keep the system-interruption reason so its warning notice remains visible.
            route.connectionDidBecomeAvailable()
        } else if pauseForUser, route.phase == .running {
            _ = route.pause()
        }
    }

    private func startWanderUITestFixture(target: MapPlace, showLocationCard: Bool) async {
        guard let origin = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) else { return }
        // Wander fixtures establish their own acknowledged origin, so cancel
        // any launch-time joystick origin lookup before staging that state.
        joystickOrigin.cancel()
        // A cold-recovery marker is display-only. Establish a confirmed
        // simulator position first so the fixture follows the same admission
        // contract as a real wander start without using GPS or network access.
        for _ in 0..<1_000 {
            if !service.nativeBusy { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        for _ in 0..<1_000 {
            if sceneActivity.isActive, !recovery.isChecking, service.movementConnection == .available { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard sceneActivity.isActive, !recovery.isChecking, service.movementConnection == .available else { return }
        if service.phase != .ready {
            guard service.phase == .stopped, service.start() else {
                return
            }
            for _ in 0..<1_000 {
                if service.phase == .ready && !service.nativeBusy { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        guard service.phase == .ready, !service.nativeBusy else { return }
        joystickOrigin.cancel()
        let originPlace = MapPlace(id: .coordinate(origin), title: "台北車站", coordinate: origin)
        guard service.teleport(to: TeleportCandidate(place: originPlace)) else { return }
        for _ in 0..<1_000 {
            if case .acknowledged(let point) = service.pointState,
               point.candidate.place.coordinate == origin { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard service.currentJoystickOrigin == origin else { return }
        for _ in 0..<1_000 {
            if service.phase == .ready, !service.nativeBusy, joystick.canStartWanderPlanning { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard service.phase == .ready, !service.nativeBusy, joystick.canStartWanderPlanning,
              sceneActivity.isActive, !recovery.isChecking else { return }
        guard let planned = try? await movement.route.planWanderSegment(from: origin, to: target.coordinate) else {
            return
        }
        guard joystick.installWanderRoute(target: WanderTarget(place: target), route: planned) else {
            return
        }
        // Teleport ACK starts the normal position-hold takeover asynchronously.
        // Wait for that simulator write to drain before the fixture admits wander.
        for _ in 0..<1_000 {
            if !service.nativeBusy, joystick.canSetWanderEnabled { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !service.nativeBusy, joystick.canSetWanderEnabled else { return }
        guard joystick.setWanderEnabled(true) else {
            return
        }
        for _ in 0..<1_000 {
            if joystick.wanderEnabled && joystick.phase == .moving { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        if showLocationCard, joystick.wanderEnabled {
            selectedWanderPlace = target
        }
    }
#endif

    private func observeMapInputs<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(service.$error, perform: handleServiceError)
            .onChange(of: service.preparedOperation?.id) { _, id in
                if id != nil { dismissKeyboard() }
            }
            .onReceive(location.$observation) { handleRealLocationObservation($0) }
            .onChange(of: route.picker?.id) { _, id in
                if id != nil {
                    searchFocusRequest = UUID()
                } else {
                    searchFocusRequest = nil
                    dismissKeyboard()
                }
            }
            .onChange(of: route.plannedRoute) { _, planned in
                // Whenever the planned route changes while editing, the camera frames the whole route.
                guard let planned else { return }
                if mode == .route, route.canEdit { cameraIntent = GoFlyCameraIntent(route: planned) }
            }
            .onChange(of: mode) { _, mode in
                if mode != .joystick { wander.cancelAll() }
                if mode == .joystick {
                    service.warmupSession()
                        if !recovery.isChecking { wander.resumePending() }
                }
                if mode == .teleport && (positionHold.phase == .paused || positionHold.phase == .completed) {
                    sheetDetent = .collapsed
                }
                dismissKeyboard()
                checkpoints.capture(recovery.snapshot(mode: mode))
            }
    }

    private func observeMapScene<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                sceneActivity.isActive = phase == .active
                Diagnostics.shared.record("movement.scene", category: .movement, level: .notice, [
                    "phase": .text(String(describing: phase)),
                    "route": .text(String(describing: route.phase)),
                    "joystick": .text(String(describing: joystick.phase)),
                    "service": .text(service.phase.rawValue),
                    "grant": .flag(continuation.hasRuntime)
                ])
                sceneSettleTask?.cancel()
                if phase == .active {
                    sceneSettleTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        sceneSettled = true
                    }
                } else {
                    sceneSettled = false
                }
                if phase == .active {
                    checkpoints.sceneBecameActive()
                    location.sceneDidBecomeActive()
                    continuation.sceneDidBecomeActive()
                    movement.keepAlive.sceneDidBecomeActive()
                    recovery.requestForegroundCheck()
                } else {
                    wander.cancelUncommitted()
                    location.sceneDidBecomeInactive()
                    continuation.releaseForInactiveScene()
                    movement.keepAlive.releaseForInactiveScene()
                    checkpoints.sceneLeftForeground(recovery.snapshot(mode: mode))
                }
            }
            .onChange(of: recovery.isChecking) { _, checking in
                if !checking && scenePhase == .active { wander.resumePending() }
            }
            .onChange(of: service.movementConnection) { _, state in
                if state == .available {
                        if scenePhase == .active && !recovery.isChecking { wander.resumePending() }
                } else {
                    wander.cancelUncommitted()
                }
            }
            .onChange(of: recovery.checkpointRevision) { _, _ in
                checkpoints.capture(recovery.snapshot(mode: mode))
            }
    }

    private func observeMapMovement<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(GoFlyPathMonitor.shared.changes) { _ in recovery.networkPathDidChange() }
            .onChange(of: joystick.wanderEnabled) { _, enabled in
                if !enabled { wanderSearch.resetSelection() }
            }
            .onChange(of: joystick.wanderNeedsReplan) { _, needsReplan in
                if needsReplan, joystick.phase == .moving { wander.replanCurrentDestination() }
            }
            .onChange(of: joystick.wanderNeedsTarget) { _, needsTarget in
                if needsTarget { wander.planNextSegment() }
            }
            .onChange(of: joystick.phase) { _, phase in
                if joystick.wanderNeedsReplan, phase == .moving { wander.replan(to: joystick.wanderTarget?.place) }
            }
            .onChange(of: positionHold.phase) { _, phase in
                guard mode == .teleport, (phase == .paused || phase == .completed) else { return }
                sheetDetent = .collapsed
            }
    }

    private func observeMapPresentation<Content: View>(_ content: Content) -> some View {
        content
            .task(id: route.completion?.executionID) { await dismissRouteCompletionWhenReady() }
            // The range stays where the first known position was until a teleport moves it;
            // joystick movement and a running wander never drag the circle along.
            .onChange(of: service.currentJoystickOrigin, initial: true) { _, origin in
                if let origin { wanderRange.adoptAnchorIfNeeded(origin) }
            }
            .onChange(of: service.pointState) { _, state in
                switch state {
                case .acknowledged(let intent):
                    search.clearCandidate(ifMatching: intent.candidate.id)
                    // Only a teleport the person confirmed moves the camera; a
                    // joystick or wander origin is set without touching it.
                    let automaticOrigin = joystickOrigin.isOrigin(intent.id) || wander.isStartOrigin(intent.id)
                    if search.candidate == nil, !automaticOrigin {
                        cameraIntent = GoFlyCameraIntent(coordinate: intent.candidate.place.coordinate)
                    }
                    dismissKeyboard()
                    // The range follows a teleport only while no wander runs; the joystick's
                    // automatic origin fix just restores the position it already had.
                    if !joystickOrigin.isOrigin(intent.id) {
                        wanderRange.teleportAcknowledged(at: intent.candidate.place.coordinate,
                                                         wanderRunning: joystick.wanderEnabled)
                    }
                    if joystickOrigin.settle(intent.id), mode == .teleport && search.candidate == nil { mode = .joystick }
                    wander.originAcknowledged(intent.id)
                case .notSent(let intent, _):
                    joystickOrigin.settle(intent.id)
                    wander.originNotSent(intent.id)
                case .unconfirmed(let intent, _):
                    joystickOrigin.settle(intent.id)
                    wander.originUnconfirmed(intent.id)
                default:
                    break
                }
            }
    }

    private var favoritesView: some View {
        GoFlyFavoritesView(
            candidate: activeSearch.candidate?.place,
            onSelect: { selectSearchPlace($0); presentedSheet = nil },
            onSearch: { showingSearch = true; presentedSheet = nil },
            onDismiss: { presentedSheet = nil }
        )
    }

    private func detailsView(_ place: MapPlace) -> some View {
        GoFlyPlaceDetailsView(place: place, titleLabel: favorites.favorite(for: place)?.label,
                              onDismiss: { presentedSheet = nil })
    }

    private var favoritesShown: Bool {
        if case .favorites = presentedSheet?.content { return true }
        return false
    }

    private var detailsCoverBinding: Binding<MapPlace?> {
        Binding(
            get: {
                if case .details(let place) = presentedSheet?.content { return place }
                return nil
            },
            set: { if $0 == nil, case .details = presentedSheet?.content { presentedSheet = nil } })
    }

    private var searchScreen: some View {
        Group {
            if let picker = route.picker {
                GoFlySearchPanel(
                    search: picker.candidates,
                    focusRequest: searchFocusRequest,
                    placeholderOverride: "",
                    accessibilityLabelOverride: routePickerAccessibilityLabel(picker.role),
                    roleTitle: goFlyLocalizedFormat(goFlyString("route.picker.selecting"), goFlyRouteRoleTitle(picker.role)),
                    onBack: { route.cancelPicker(id: picker.id) },
                    onFavorites: { searchFavorites = true },
                    recentPlaces: recentPlaces,
                    onClearRecentPlaces: clearRecentPlaces,
                    onSelect: { place in
                        recordRecentPlace(place)
                        _ = route.confirmPicker(id: picker.id)
                    },
                    onUseCurrentLocation: picker.allowsCurrent
                        ? {
                                _ = route.confirmPicker(id: picker.id, useCurrentLocation: true)
                        } : nil
                )
            } else {
                GoFlySearchPanel(
                    search: activeSearch,
                    focusRequest: searchFocusRequest,
                    placeholderOverride: "",
                    onBack: { showingSearch = false },
                    onFavorites: { searchFavorites = true },
                    recentPlaces: recentPlaces,
                    fixtureCoordinateResult: uiTestFixtureFrame == "B4" ? GoFlyUITestOverrides.searchCoordinateResult : nil,
                    fixtureNearbyResults: uiTestFixtureFrame == "B4" ? GoFlyUITestOverrides.searchNearbyResults : nil,
                    onClearRecentPlaces: clearRecentPlaces,
                    onSelect: selectSearchPlace)
            }
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $searchFavorites) {
            GoFlyFavoritesView(candidate: activeSearch.candidate?.place,
                onSelect: { place in
                    activeSearch.select(place)
                    searchFavorites = false
                    if let picker = route.picker {
                        _ = route.confirmPicker(id: picker.id)
                    } else { selectSearchPlace(place) }
                }, onSearch: { searchFavorites = false }, onDismiss: { searchFavorites = false })
            .goFlyPushedFullScreen()
        }
    }

    private func routePickerAccessibilityLabel(_ role: RouteNodeRole) -> String {
        switch role {
        case .start: goFlyString("route.chooseOrigin")
        case .destination: goFlyString("route.chooseDestination")
        case .waypoint(let number):
            goFlyLocalizedFormat(goFlyString("route.chooseWaypoint"), number)
        }
    }

    @ViewBuilder
    private func mapContent(in geometry: GeometryProxy) -> some View {
        let viewport = visibleViewport(in: geometry)
        let mapSafeInsets = geometry.safeAreaInsets
        let mapViewport = viewport.offsetBy(dx: mapSafeInsets.leading, dy: mapSafeInsets.top)
        let mapSize = CGSize(
            width: geometry.size.width + mapSafeInsets.leading + mapSafeInsets.trailing,
            height: geometry.size.height + mapSafeInsets.top + mapSafeInsets.bottom
        )
        ZStack(alignment: .topLeading) {
            mapCanvas(viewport: mapViewport, size: mapSize,
                      attributionBottomInset: attributionBottomInset(in: geometry))
                .ignoresSafeArea()
            mapPins(viewport: mapViewport)
                .ignoresSafeArea()
            topChrome
            if showsMapControls { mapControls(in: geometry) }
            bottomChrome(in: geometry)
        }
        .overlay(alignment: .top) {
            toastStack(topInset: (topFrame.maxY > 0 ? topFrame.maxY : 116) + 8)
        }
        .goFlySnackbar(
            $snackbar,
            bottomPadding: snackbarBottomOffset(in: geometry),
            duration: uiTestFixtureFrame == "B6" ? .seconds(30) : nil
        )
        .onChange(of: joystick.error) { _, newError in notices.reopen(.joystickError, ifPresent: newError) }
        .onChange(of: service.clearState) { _, state in
            // Real GPS can be observed again once the simulated location is cleared.
            if case .confirmed = state { location.refresh() }
        }
        .onChange(of: mode) { _, newMode in
            if newMode != .route { pendingRouteNodeTapID = nil }
        }
        .onChange(of: route.draft) { _, _ in
            pendingRouteNodeTapID = nil
            notices.clearFavoriteRouteFailure()
        }
        .onChange(of: route.error) { _, newError in notices.reopen(.routeError, ifPresent: newError) }
        .onChange(of: recovery.noticeKey) { _, newKey in notices.reopen(.recovery, ifPresent: newKey) }
        .onChange(of: continuation.noticeKey) { _, newKey in notices.reopen(.continuation, ifPresent: newKey) }
    }

    private func toastStack(topInset: CGFloat) -> some View {
        GoFlyToastOverlay(topInset: topInset) {
            GoFlyMapToastStack(
                service: service, route: route, joystick: joystick, recovery: recovery,
                continuation: continuation, positionHold: positionHold, joystickOrigin: joystickOrigin,
                wander: wander, notices: $notices,
                searchPasteWarning: $searchPasteWarning,
                showingSettings: $showingSettings,
                mode: mode, sceneSettled: sceneSettled, isResumeState: isResumeState)
        }
        .zIndex(50)
    }

    @ViewBuilder
    private var topChrome: some View {
        if isExecutionMode || isWanderMap {
            VStack(alignment: .leading, spacing: GoFlyStyle.statusPillTopSpacing) {
                GoFlyExecutionHeader(
                    title: executionTitle,
                    detail: executionDetail,
                    symbol: executionSymbol,
                    onTrailingAction: nil
                )
                GoFlyStatusPill(text: pillText, tone: pillTone, identifier: "map.statusPill")
                    .accessibilityValue(goFlyString(movement.status.textKey))
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                updateMeasuredFrame($0, from: topFrame) { topFrame = $0 }
            }
        } else {
            topBar
        }
    }

    private func snackbarBottomOffset(in geometry: GeometryProxy) -> CGFloat {
        if activeCandidate != nil, mode == .teleport || mode == .joystick {
            // The card's bottom edge is the safe-area bottom, where this overlay ends, so the
            // copy toast sits 8 pt above the card's measured top edge.
            return (teleportCardFrame.height > 0 ? teleportCardFrame.height : 180) + 8
        }
        if mode == .teleport {
            // The collapsed teleport panel's copy snackbar sits 8 pt above its top edge.
            return max(0, geometry.size.height - panelFrame.minY) + 8
        }
        if mode == .route, route.canEdit, route.picker == nil, activeCandidate == nil, showsBottomBar {
            // Route editing: a snackbar covers the Start row,
            // which sits 36 pt above the tab bar.
            let startCenter = bottomBarHeight - geometry.safeAreaInsets.bottom + 36 + GoFlyStyle.primaryButtonHeight / 2
            return max(0, startCenter - 28)
        }
        if activeCandidate != nil || wanderCardPlace != nil {
            // This card's measured frame includes its safe-area bottom padding.
            let cardHeight = bottomCardFrame.height > 0 ? bottomCardFrame.height - geometry.safeAreaInsets.bottom : 180
            return cardHeight + 8
        } else {
            let panelTop = (showsBottomBar ? bottomBarHeight : geometry.safeAreaInsets.bottom) + max(currentCollapsedHeight, sheetHeight)
            // The snackbar overlay ends at the safe-area bottom, which the bar and panel already include.
            return panelTop - geometry.safeAreaInsets.bottom + 12
        }
    }

    /// Mark the actual road entrances; selected POIs remain in the editing fields.
    private var manualRouteWaypoints: [GeoCoordinate] {
        route.plannedRoute?.waypoints ?? []
    }

    /// Distance from the screen bottom to the top of whatever covers the map there.
    private func attributionBottomInset(in geometry: GeometryProxy) -> CGFloat {
        var top = panelFrame.height > 0 ? panelFrame.minY : geometry.size.height
        if (mode == .teleport || mode == .joystick) && !isWanderMap && activeCandidate != nil
            && teleportCardFrame.height > 0 {
            top = min(top, teleportCardFrame.minY)
        }
        if ((mode == .route && activeCandidate != nil) || (isWanderMap && wanderCardPlace != nil))
            && bottomCardFrame.height > 0 {
            top = min(top, bottomCardFrame.minY)
        }
        // The map runs under the bottom safe area, which mapRoot's frames exclude;
        // keep the Maps logo 4 pt above whatever covers it.
        return max(0, geometry.size.height - top) + geometry.safeAreaInsets.bottom + 4
    }

    /// The range circle belongs to the joystick tab (E1 and E2). Until a teleport or
    /// wander start fixes an anchor, it is centred where an automatic wander would
    /// start: the current joystick origin, else the map's wander origin candidate.
    private var rangeCircle: GoFlyRangeCircle? {
        guard mode == .joystick, route.picker == nil, wanderRange.isVisible else { return nil }
        return rangeGeometry
    }

    /// The circle regardless of whether it is drawn: what "fit range" frames.
    private var rangeGeometry: GoFlyRangeCircle? {
        guard let center = wanderRange.anchor ?? service.currentJoystickOrigin
                ?? mapWanderOriginCandidates().first else { return nil }
        return GoFlyRangeCircle(center: center, radiusMeters: wanderRange.radius.meters)
    }

    /// Joystick and wander frame the range circle, not the route; the route is the fallback.
    private func wanderFitIntent(_ planned: PlannedRoute) -> GoFlyCameraIntent {
        rangeGeometry.map { GoFlyCameraIntent(range: $0) } ?? GoFlyCameraIntent(route: planned)
    }

    private func mapCanvas(viewport: CGRect, size: CGSize, attributionBottomInset: CGFloat) -> some View {
        let cameraViewport = activeCandidate == nil
            ? viewport
            : CGRect(origin: .zero, size: size)
        var canvas = GoFlyMapCanvas(
            marker: movement.presentation.marker, candidate: activeCandidate,
            viewport: cameraViewport, cameraIntent: cameraIntent,
            route: mode == .route ? route.plannedRoute : (isWanderMap ? joystick.wanderRoute : nil),
            // A wander segment has one destination and no intermediate stops.
            routeWaypoints: mode == .route && route.draft.gpxSource == nil ? manualRouteWaypoints : (isWanderMap ? [] : nil),
            wanderTarget: isWanderMap ? joystick.wanderTarget?.place : nil,
            rangeCircle: rangeCircle,
            markerBearingDegrees: activeMarkerBearing,
            markerRoute: isWanderMap ? (joystick.wanderNeedsReplan ? nil : joystick.wanderRoute) : movement.presentation.route,
            markerRouteDistance: isWanderMap ? joystick.wanderProgressMeters : movement.presentation.routeDistance,
            adjustsFocusForViewportChanges: false,
            attributionBottomInset: attributionBottomInset,
            onDestinationTap: isWanderMap && joystick.wanderTarget != nil ? {
                dismissKeyboard()
                selectedWanderPlace = joystick.wanderTarget?.place
            } : nil,
            onMapTap: { coordinate in
                if let picker = route.picker {
                    picker.candidates.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if mode == .route, route.canEdit, route.draft.isManual {
                    // D4: a map Pin fills the selected field only after "確認".
                    search.selectMapCoordinate(coordinate, resolver: mapPlaces)
                    cameraIntent = GoFlyCameraIntent(coordinate: coordinate, ensureVisibleOnly: true)
                    sheetDetent = .collapsed
                } else if isWanderMap {
                    wanderSearch.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if (mode == .teleport || mode == .joystick), route.canEdit {
                    search.selectMapCoordinate(coordinate, resolver: mapPlaces)
                    cameraIntent = GoFlyCameraIntent(coordinate: coordinate, ensureVisibleOnly: true)
                    sheetDetent = .collapsed
                }
            },
            onProjection: {
                MapKitSearchRegionContext.current = $0.searchRegion
                // The map's centre and visible search region can move without
                // a pin. Keep the search context fresh, but only publish a
                // SwiftUI state update when the candidate/wander overlay uses
                // projection coordinates. Otherwise each MapKit layout pass
                // needlessly invalidates the whole map sheet hierarchy.
                if activeCandidate != nil || isWanderMap || mode == .joystick || projection == nil, projection != $0 {
                    projection = $0
                }
            }
        )
#if DEBUG && targetEnvironment(simulator)
        canvas.usesOfflineFixtureTiles = uiTestFixtureFrame != nil
        // B8 is designed with a confirmed GPS arrow. The fixture has no Core
        // Location provider, so render that glyph without changing movement state.
        canvas.usesFixtureRealLocationStyle = uiTestFixtureFrame == "B8"
#endif
        return canvas
    }

    @ViewBuilder
    private func mapPins(viewport: CGRect) -> some View {
        // The wander destination is the route's destination dot on the map canvas;
        // only a picked replacement draws a pin here.
        if let candidate = activeCandidate, let point = projection?.candidatePoint {
            if isWanderMap {
                if viewport.contains(point) {
                    wanderPinOverlay(at: point, size: CGSize(width: max(84, goWidth), height: candidateHeight),
                                     viewport: viewport, avoiding: projection?.wanderTargetPoint) {
                        candidatePin(candidate)
                    }
                }
            } else {
                candidatePin(candidate)
                    .position(x: point.x, y: point.y - candidateHeight / 2)
            }
        }
    }

    private func bottomChrome(in geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if isExecutionMode {
                    bottomPanelContent(in: geometry)
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                        .background(GoFlyStyle.cardSurface)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                            updateMeasuredFrame($0, from: panelFrame) {
                                panelFrame = $0
                                updateMeasuredHeight($0.height, from: sheetHeight) { sheetHeight = $0 }
                            }
                        }
                } else {
                    GoFlyBottomSheet(
                        detent: $sheetDetent,
                        availableHeight: sheetAvailableHeight(in: geometry),
                        collapsedHeight: currentCollapsedHeight,
                        maximumHeight: sheetMaxHeight(in: geometry),
                        contentHeight: bottomContentHeight,
                        fitsContent: sheetFitsContent,
                        preferredHeight: sheetPreferredHeight,
                        backgroundOpacity: mode == .joystick ? 0.96 : 1,
                        onHeightChange: { updateMeasuredHeight($0, from: sheetHeight) { sheetHeight = $0 } }
                    ) {
                        sheetContent(in: geometry)
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                        updateMeasuredFrame($0, from: panelFrame) { panelFrame = $0 }
                    }
                }
                if showsBottomBar {
                    GoFlyBottomBar(selection: Binding(get: { mode }, set: { selectMode($0) }),
                                     bottomInset: geometry.safeAreaInsets.bottom)
                        .disabled(!canSwitchMode)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                            updateMeasuredHeight($0, from: bottomBarHeight) { bottomBarHeight = $0 }
                        }
                }
            }
            if isWanderMap, let place = wanderCardPlace {
                wanderLocationCard(for: place)
                    .padding(.horizontal, 16)
                    // E4: the same bottom distance as the B5 / B7 / D4 location cards.
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                        updateMeasuredFrame($0, from: bottomCardFrame) { bottomCardFrame = $0 }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
            if mode == .route, let candidate = activeCandidate {
                GoFlyLocationCard(
                    place: candidate.place,
                    titleLabel: favorites.favorite(for: candidate.place)?.label,
                    primaryActionType: .confirm,
                    primaryActionTitle: goFlyString("common.confirm"),
                    onPrimaryAction: { confirmRouteCandidate(candidate) },
                    onDismiss: {
                        activeSearch.resetSelection()
                        if isMapPicking {
                            isMapPicking = false
                        }
                        sheetDetent = .expanded
                    },
                    onCopy: {
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    },
                    distanceFrom: service.positionMarker?.coordinate,
                    identifier: "map.route.confirmCard"
                )
                .padding(.horizontal, 16)
                // Same bottom distance as the B5 / B7 / E4 location cards.
                .padding(.bottom, geometry.safeAreaInsets.bottom)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                    updateMeasuredFrame($0, from: bottomCardFrame) { bottomCardFrame = $0 }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
            if (mode == .teleport || (mode == .joystick && !joystick.wanderEnabled)), let candidate = activeCandidate {
                GoFlyLocationCard(
                    place: candidate.place,
                    titleLabel: locationCardTitleLabel(for: candidate.place),
                    primaryActionType: .teleport,
                    primaryEnabled: !isGoButtonDisabled,
                    onPrimaryAction: {
                        performGo(candidate)
                    },
                    onDismiss: {
                        activeSearch.resetSelection()
                    },
                    onCopy: {
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    },
                    distanceFrom: service.positionMarker?.coordinate,
                    identifier: mode == .joystick ? "map.joystick.locationCard" : "map.teleport.locationCard"
                )
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { frame in
                    // Exclude the outer bottom padding from the card bounds.
                    let cardFrame = CGRect(x: frame.minX, y: frame.minY,
                                           width: frame.width, height: frame.height - geometry.safeAreaInsets.bottom)
                    updateMeasuredFrame(cardFrame, from: teleportCardFrame) { teleportCardFrame = $0 }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: activeCandidate != nil) { _, hasCandidate in
            if hasCandidate {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    sheetDetent = .collapsed
                }
            } else if mode == .joystick, !isWanderMap {
                // Manual joystick: after Go or closing the card the pad is available again.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    sheetDetent = .expanded
                }
            }
        }
        .onChange(of: wanderCardPlace != nil) { _, hasCard in
            guard hasCard, isWanderMap else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                sheetDetent = .collapsed
            }
        }
        .onChange(of: service.clearState) { _, state in
            guard state == .confirmed, service.coldClearPending else { return }
            Task {
                if await recoveryStore.clearMovementState() { service.finishColdClear() }
            }
        }
        .onChange(of: showsOperationPanel) { _, shown in
            if shown { sheetDetent = .expanded }
        }
        .onChange(of: route.picker?.id) { _, id in
            // D5 picks collapse the sheet while a candidate is selected; closing it returns to D1.
            if id != nil || !isMapPicking { sheetDetent = .expanded }
        }
    }

    private func sheetContent(in geometry: GeometryProxy) -> some View {
        bottomPanelContent(in: geometry)
            .fixedSize(horizontal: false, vertical: sheetFitsContent)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                updateMeasuredHeight($0, from: bottomContentHeight) { bottomContentHeight = $0 }
            }
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private func sheetAvailableHeight(in geometry: GeometryProxy) -> CGFloat {
        max(200, geometry.size.height - (showsBottomBar ? 49 : 0))
    }

    private func bottomPanelContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            modePanel(in: geometry)
        }
    }

    private var activeMovement: ActiveMovement? { movement.activeMovement }

    private var isResumeState: Bool {
        if continuation.noticeKey != nil && !notices.isDismissed(.continuation) { return true }
        guard let active = activeMovement, active.isResumable else { return false }
        switch active.kind {
        case .route: return true
        case .wander: return mode == .joystick && !joystick.wanderNeedsReplan
        case .positionHold: return mode == .teleport
        case .joystick: return false
        }
    }

    private var isTeleportHoldRecovery: Bool {
        guard mode == .teleport, let active = activeMovement, active.kind == .positionHold else { return false }
        return active.runState == .paused || active.runState == .completed
    }


    private var currentCollapsedHeight: CGFloat {
        // Minimum heights on the 4 pt grid: teleport 120 (B1/B8/B9), others 96 = 33 pt grabber row + content.
        if isWanderRunning { return 120 }
        return mode == .teleport ? 120 : 96
    }

    private func modePanel(in geometry: GeometryProxy) -> some View {
        Group {
            if mode == .joystick, route.canEdit, route.picker == nil {
                if isResumeState && !isWanderReplanning && [.paused, .suspended, .interrupted].contains(joystick.phase) {
                    GoFlyResumePanel(
                        title: goFlyString("joystick.wanderPaused"),
                        ctaTitle: goFlyString("wander.resumeShort"),
                        onResume: { _ = joystick.resume() },
                        isEnabled: joystick.canResume,
                        contentHeight: 64,
                        identifier: "joystick.resumePanel"
                    )
                } else {
                    ZStack(alignment: .bottom) {
                        GoFlyJoystickPanel(
                            controller: joystick, cameraHeadingDegrees: projection?.cameraHeadingDegrees ?? 0,
                            maximumHeight: isExecutionMode ? max(180, geometry.size.height - topFrame.maxY - 120) : contentMaximumHeight(in: geometry),
                            isCollapsed: sheetDetent == .collapsed,
                            bottomPadding: isWanderRunning ? (sheetDetent == .collapsed ? 24 : 40) + geometry.safeAreaInsets.bottom : nil,
                            onRandomDestination: {
                                wander.replan(to: nil)
                            },
                            onStartWander: { wander.start() },
                            onNeedsOrigin: { joystickOrigin.establishFromMap() },
                            canStartWander: canRequestWanderStart,
                            isStartingWander: wander.isStarting,
                            onStopWander: { wander.stop() },
                            onSettings: { showingSettings = true },
                            wanderRadius: wanderRange.radius,
                            onWanderRadiusChanged: { wanderRange.setRadius($0) }
                        )
                        // Keep an admitted finger alive through preparation; disappearance releases it.
                        .opacity(showsOperationPanel ? 0 : 1)
                        .accessibilityHidden(showsOperationPanel)
                        if showsOperationPanel { operationPanel(in: geometry) }
                    }
                }
            } else if showsOperationPanel {
                operationPanel(in: geometry)
            } else if mode == .route || !route.canEdit {
                // D10 / D10.a: a paused or interrupted route keeps the running panel; only the button turns into 繼續.
                GoFlyRoutePanel(
                    controller: route, showingFavoriteRoutes: $showingFavoriteRoutes,
                    showingImportedRoutes: $showingImportedRoutes, showingAllPoints: $showingAllImportedPoints,
                    maximumHeight: isExecutionMode ? max(180, geometry.size.height - topFrame.maxY - 120) : contentMaximumHeight(in: geometry),
                    onEditNode: selectRouteNode,
                    bottomSafeInset: geometry.safeAreaInsets.bottom,
                    onInspectRoute: {
                        pendingRouteNodeTapID = nil
                        showingRouteList = true
                    },
                    onRequestEnd: { _ = route.cancel() },
                    onSettings: { showingSettings = true },
                    onNotice: { notices.showFavoriteRouteFailure($0) },
                    onRetryInterrupted: { retryInterruptedRoute() },
                    onFocusPoint: { cameraIntent = GoFlyCameraIntent(coordinate: $0) },
                    currentLocationAvailable: service.currentRouteOrigin != nil,
                    currentRouteOrigin: { service.currentRouteOrigin },
                    isNarrow: sheetDetent == .collapsed || isMapPicking || (mode == .route && activeCandidate != nil),
                    onExpand: { sheetDetent = .expanded }
                )
            } else {
                // B8/B9 keep the standard collapsed Teleport panel; recovery is in the top warning toast.
                teleportContent
            }
        }
    }

    private var isExecutionMode: Bool { !route.canEdit }

    private var executionTitle: String {
        if joystick.wanderEnabled { return joystick.wanderTarget?.place.title ?? goFlyString("joystick.wander") }
        if case .place(let place) = route.draft.destination?.value {
            let paused = [.paused, .interrupted].contains(route.phase)
            return goFlyLocalizedFormat(goFlyString(paused ? "route.heading.paused" : "route.heading.going"), place.title)
        }
        return goFlyString("mode.route")
    }

    private var executionSymbol: GoFlyIconAsset {
        if joystick.wanderEnabled {
            return [.paused, .suspended, .interrupted].contains(joystick.phase) ? GoFlySymbols.pause : GoFlySymbols.heading
        }
        return [.paused, .interrupted].contains(route.phase) ? GoFlySymbols.pause : GoFlySymbols.heading
    }

    private var executionDetail: String {
        if joystick.wanderEnabled {
            let speed = goFlyLocalizedFormat(goFlyString("route.speedValue"), joystick.speed.kilometersPerHour)
            if isWanderReplanning { return goFlyString("wander.planning") + " · " + speed }
            guard let planned = joystick.wanderRoute else {
                return goFlyString("joystick.phase.\(joystick.phase.rawValue)") + " · " + speed
            }
            let remaining = max(0, planned.totalDistanceMeters - joystick.wanderProgressMeters)
            let minutes = Int(ceil(remaining / max(joystick.speed.metersPerSecond, 0.1) / 60))
            return goFlyLocalizedFormat(goFlyString("route.distance"), remaining / 1_000) + " · "
                + goFlyLocalizedFormat(goFlyString("route.duration"), minutes) + " · " + speed
        }
        let speed = goFlyLocalizedFormat(goFlyString("route.speedValue"), route.draft.speed.kilometersPerHour)
        guard !route.roundTripEnabled, let progress = route.progress else {
            return goFlyString("route.phase.\(route.phase.rawValue)") + " · " + speed
        }
        let remaining = max(0, route.heading == .reverse
            ? progress.committedDistanceMeters
            : progress.totalDistanceMeters - progress.committedDistanceMeters)
        let minutes = Int(ceil(Double(max(0, progress.estimatedRemaining.components.seconds)) / 60))
        return goFlyLocalizedFormat(goFlyString("route.distance"), remaining / 1_000) + " · "
            + goFlyLocalizedFormat(goFlyString("route.duration"), minutes) + " · " + speed
    }

    private func selectSearchPlace(_ place: MapPlace) {
        activeSearch.select(place)
        recordRecentPlace(place)
        cameraIntent = GoFlyCameraIntent(coordinate: place.coordinate)
        if mode == .teleport {
            sheetDetent = .collapsed
        } else {
            sheetDetent = .expanded
        }
        showingSearch = false
    }

    private func recordRecentPlace(_ place: MapPlace) {
        recentPlaces.removeAll { $0.coordinate == place.coordinate }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(8))
    }

    private func clearRecentPlaces() {
        withAnimation(.easeInOut(duration: 0.2)) {
            recentPlaces.removeAll()
        }
    }

    private func dismissRouteCompletionWhenReady() async {
        guard let id = route.completion?.executionID else { return }
        snackbar = GoFlySnackbarMessage(text: goFlyString("route.completed"))
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        route.dismissCompletion(executionID: id)
    }

    private func performGo(_ candidate: TeleportCandidate) {
        dismissKeyboard()
        joystickOrigin.go(to: candidate)
    }

    private func confirmWanderDestination(_ place: MapPlace) {
        guard isWanderMap, joystick.canApplyWanderTarget else { return }
        dismissKeyboard()
        wander.confirmDestination(place)
    }

    /// D4 "確認": the Pin or Location Card fills the selected field and returns to D1.
    private func confirmRouteCandidate(_ candidate: TeleportCandidate) {
        if let picker = route.picker {
            _ = route.confirmPicker(id: picker.id)
        } else {
            _ = route.confirmSelectedNode(with: candidate.place)
        }
        isMapPicking = false
        activeSearch.resetSelection()
        sheetDetent = .expanded
    }

    private var teleportContent: some View {
        Group {
            if sheetDetent == .collapsed || isTeleportHoldRecovery {
                collapsedPositionSummary
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                expandedTeleportContent
            }
        }
    }

    /// Figma B1/B8/B9: the collapsed Teleport sheet keeps its position summary
    /// and favorite/copy actions, including while a position hold is paused.
    private var collapsedPositionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goFlyString(collapsedPositionTitleKey))
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPositionTitle)
                        .goFlyFont(GoFlyFont.title)
                        .monospacedDigit()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let coordinate = service.positionMarker?.coordinate {
                        Text(coordinate.displayText)
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let coordinate = service.positionMarker?.coordinate {
                    let place = currentPositionPlace ?? MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                                         coordinate: coordinate)
                    GoFlyFavoriteStar(place: place, identifier: "map.position.favorite", allowsDelete: true)
                    GoFlyCopyIconButton(coordinate: coordinate, identifier: "map.position.copy") {
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.collapsedPosition")
    }

    private var collapsedPositionTitleKey: String {
#if DEBUG && targetEnvironment(simulator)
        if uiTestFixtureFrame == "B8" { return "sheet.realPosition" }
#endif
        if hasFreshRealGPS { return "sheet.realPosition" }
        if positionHold.phase == .paused || positionHold.phase == .completed {
            return "sheet.lastSimulatedPosition"
        }
        return service.positionMarker?.source == .simulation ? "sheet.currentPosition" : "sheet.realPosition"
    }

    /// Reuse known place metadata; a visual summary never starts location work.
    private var currentPositionPlace: MapPlace? {
        guard let coordinate = service.positionMarker?.coordinate else { return nil }
        if let favorite = currentPositionFavorite {
            return MapPlace(id: .coordinate(coordinate), title: favorite.place.title,
                            coordinate: coordinate, address: favorite.place.address)
        }
        return recentPlaces.first(where: { $0.coordinate == coordinate })
            ?? MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private var currentPositionFavorite: FavoritePlace? {
        guard let coordinate = service.positionMarker?.coordinate else { return nil }
        return favorites.favorites.first { $0.place.coordinate == coordinate }
    }

    private var currentPositionTitle: String {
        guard let place = currentPositionPlace else { return goFlyString("sheet.noPosition") }
        return GoFlyLocationTitle.resolve(for: place)
    }

    private func locationCardTitleLabel(for place: MapPlace) -> String? {
        return favorites.favorite(for: place)?.label
    }

    private var expandedTeleportContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedPositionSummary
                .padding(.bottom, 12)
            Rectangle()
                .fill(GoFlyStyle.subtleBorder)
                .frame(height: 0.5)
            teleportSectionHeader("favorites.title", actionTitle: "search.viewAll") {
                presentedSheet = GoFlyMapSheet(content: .favorites)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            // Figma B2 shows the first two favorites in their persisted order.
            VStack(spacing: 0) {
                ForEach(visibleTeleportFavorites.indices, id: \.self) { index in
                    let favorite = visibleTeleportFavorites[index]
                    teleportPlaceRow(favorite.place, title: favorite.displayTitle,
                                     identifier: "favorites.place.\(favorite.place.coordinate.displayText)",
                                     showsSeparator: index < visibleTeleportFavorites.count - 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func teleportSectionHeader(_ key: String, actionTitle: String? = nil,
                                       action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(goFlyString(key))
                .goFlyFont(GoFlyFont.subheadlineEmphasis)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                // Figma: Ghost Secondary button.
                Button(goFlyString(actionTitle), action: action)
                    .buttonStyle(GoFlyButtonStyle(variant: .ghostSecondary, size: .inline, expandsToFill: false))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("favorites.open")
            }
        }
    }

    private var visibleTeleportFavorites: [FavoritePlace] {
        Array(favorites.favorites.prefix(2))
    }

    /// The star opens the label editor (C2); the rest of the row selects the place.
    private func teleportPlaceRow(_ place: MapPlace, title: String, identifier: String,
                                  showsSeparator: Bool) -> some View {
        GoFlyListRow(minimumHeight: 64, separatorLeadingInset: showsSeparator ? 48 : nil) {
            HStack(spacing: 8) {
                GoFlyFavoriteStar(place: place, identifier: "\(identifier).favorite", circleDiameter: 36,
                                  allowsDelete: true)
                    .padding(.leading, -4)
                Button { selectSearchPlace(place) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .goFlyFont(GoFlyFont.headline)
                                .foregroundStyle(GoFlyTextColor.primary)
                                .lineLimit(1)
                            Text(place.address ?? place.coordinate.displayText)
                                .goFlyFont(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
            }
        }
    }

    private func operationPanel(in geometry: GeometryProxy) -> some View {
        GoFlyOperationPanel(
            operation: service.preparedOperation,
            unconfirmedFailure: unconfirmedFailure,
            nativeBusy: service.nativeBusy,
            maximumHeight: panelMaximumHeight(in: geometry),
            reasonIdentifier: "map.serviceError.message",
            cancelIdentifier: "map.serviceError.dismiss",
            onCancel: cancelPreparation,
            onRetry: { _ = service.retryPreparedOperation(id: $0) },
            onSettings: { showingSettings = true },
            onReturn: { notices.leaveUnconfirmed(unconfirmedID) }
        )
    }

    private func selectMode(_ value: GoFlyMapMode) {
        joystickOrigin.cancel()
        mode = value
        // Tapping any tab restores a panel that is at its minimum height.
        if value != .teleport { sheetDetent = .expanded }
        else if sheetDetent == .collapsed { sheetDetent = .half }
    }

    /// Fallback wander planning origins around the visible map center.
    private func mapWanderOriginCandidates() -> [GeoCoordinate] {
        guard let center = projection?.upperThirdCoordinate ?? projection?.centerCoordinate else { return [] }
        let latitudeOffset = min(max(projection?.searchRegionLatitudeDelta ?? 0.02, 0.005), 0.04) / 4
        let longitudeOffset = min(max(projection?.searchRegionLongitudeDelta ?? 0.02, 0.005), 0.04) / 4
        return [center,
                GeoCoordinate(latitude: center.latitude + latitudeOffset, longitude: center.longitude),
                GeoCoordinate(latitude: center.latitude - latitudeOffset, longitude: center.longitude + longitudeOffset)].compactMap { $0 }
    }

    private var wanderPlanningHost: WanderPlanningHost {
        WanderPlanningHost(
            isJoystickMode: { mode == .joystick },
            isSceneActive: { sceneActivity.isActive },
            isRecoveryChecking: { recovery.isChecking },
            mapOriginCandidates: { mapWanderOriginCandidates() },
            wanderStarted: { planned in
                cameraIntent = wanderFitIntent(planned)
            },
            segmentReplaced: { planned in
                selectedWanderPlace = nil
                wanderSearch.resetSelection()
                // Changing the place keeps the whole wander range framed.
                cameraIntent = wanderFitIntent(planned)
            },
            destinationCleared: {
                selectedWanderPlace = nil
                wanderSearch.resetSelection()
            }
        )
    }

    private var activeMarkerBearing: Double? {
        if isWanderMap { return joystickMarkerBearing }
        if mode == .route || !route.canEdit {
            return routeMarkerBearing
        }
        if mode == .joystick {
            return joystickMarkerBearing
        }
        return nil
    }

    private var routeMarkerBearing: Double? {
        guard !route.canEdit, let planned = route.plannedRoute, let progress = route.progress else { return nil }
        let distance = progress.committedDistanceMeters
        let forward = route.heading == .forward
        let deltaDistance: Double = 3.0
        let lower = max(0, distance - deltaDistance)
        let upper = min(planned.totalDistanceMeters, distance + deltaDistance)
        guard let a = planned.coordinate(at: forward ? lower : upper),
              let b = planned.coordinate(at: forward ? upper : lower), a != b else { return nil }
        return JoystickGeodesy.bearingDegrees(from: a, to: b)
    }

    private var joystickMarkerBearing: Double? {
        guard let marker = service.positionMarker, marker.source == .simulation else { return nil }
        return joystick.input?.bearingDegrees ?? joystick.smoothedWanderBearingDegrees ?? joystick.lastAcknowledgedBearingDegrees
    }

    /// Floating search entry and settings gear; execution mode supplies its own header.
    /// Floating search bar and status pill (plan 3). Paste, clear, and gear
    /// controls are independent siblings inside the rounded search field.
    private var topBar: some View {
        VStack(spacing: GoFlyStyle.statusPillTopSpacing - GoFlyStyle.statusPillHitInset) {
            GoFlyMapSearchBar(
                text: searchBarText,
                hasContent: hasSearchBarContent,
                onSearch: beginSearch,
                onClear: clearSearchBar,
                onPaste: confirmPastedSearch,
                onSettings: {
                    cancelSearchPasteConfirmation()
                    showingSettings = true
                }
            )

            HStack {
                GoFlyStatusPill(text: pillText, tone: pillTone, action: expandSheet,
                                identifier: "map.statusPill")
                    .accessibilityValue(goFlyString(movement.status.textKey))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
            updateMeasuredFrame($0, from: topFrame) { topFrame = $0 }
        }
    }

    private var searchBarText: String {
        if let candidate = activeCandidate { return candidate.place.title }
        if !search.query.isEmpty { return search.query }
        if isWanderMap, !wanderSearch.query.isEmpty { return wanderSearch.query }
        return goFlyString("search.placeholder")
    }

    private var hasSearchBarContent: Bool {
        if activeCandidate != nil { return true }
        if !search.query.isEmpty { return true }
        if isWanderMap, !wanderSearch.query.isEmpty { return true }
        return false
    }

    private func clearSearchBar() {
        cancelSearchPasteConfirmation()
        searchPasteWarning = nil
        joystickOrigin.cancel()
        activeSearch.resetSelection()
    }

    /// The only map-side control: Figma `Recenter`. It also resets the map to north,
    /// so there is no separate compass or follow-heading button.
    private func mapControls(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // Route mode only: frame the whole planned route (Figma has no variant yet).
            if mode == .route, let planned = route.plannedRoute {
                Button { cameraIntent = GoFlyCameraIntent(route: planned) } label: {
                    GoFlyIcon(GoFlySymbols.fitRoute)
                        .goFlyIconSize(size: 18)
                }
                .buttonStyle(GoFlyIconStyle(variant: .mapControls))
                .accessibilityLabel(goFlyString("map.fitRoute"))
                .accessibilityIdentifier("map.fitRoute")
            }
            if mode == .joystick {
                Button {
                    if let circle = rangeGeometry { cameraIntent = GoFlyCameraIntent(range: circle) }
                } label: {
                    GoFlyIcon(GoFlySymbols.fitRoute)
                        .goFlyIconSize(size: 18)
                }
                .buttonStyle(GoFlyIconStyle(variant: .mapControls))
                .accessibilityLabel(goFlyString("map.fitRange"))
                .accessibilityIdentifier("map.fitRange")
                // Shown: the same color as Recenter; hidden: the disabled icon color (Figma E1/E1.c).
                let foreground = wanderRange.isVisible ? GoFlyThemeColor.iconPrimary : GoFlyThemeColor.iconDisabled
                Button { wanderRange.setVisible(!wanderRange.isVisible) } label: {
                    GoFlyIcon(.radius, size: 22, maximumSize: 33)
                        .foregroundStyle(foreground)
                }
                .buttonStyle(GoFlyIconStyle(variant: .mapControls))
                .accessibilityLabel(goFlyString(wanderRange.isVisible ? "map.rangeHide" : "map.rangeShow"))
                .accessibilityIdentifier("map.range")
            }
            Button { recenter() } label: {
                GoFlyRecenterIcon(size: 22)
            }
            .buttonStyle(GoFlyIconStyle(variant: .mapControls))
            .accessibilityLabel(goFlyString("map.recenter"))
            .accessibilityHint(goFlyString("map.recenterHint"))
            .accessibilityIdentifier("map.recenter")
        }
        .padding(.trailing, 16)
        .padding(.bottom, mapControlsBottomInset(in: geometry))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func mapControlsBottomInset(in geometry: GeometryProxy) -> CGFloat {
        if (activeCandidate != nil || wanderCardPlace != nil), bottomCardFrame.height > 0 {
            return max(0, geometry.size.height - bottomCardFrame.minY + 16)
        }
        return max(0, sheetHeight + (showsBottomBar ? bottomBarHeight : 0) - geometry.safeAreaInsets.bottom) + 16
    }

    /// Floating location cards leave the recenter control visible directly above the card.
    private var showsMapControls: Bool {
        !showingSearch && route.picker == nil
    }

    /// Teleport and the route editor size the sheet to their content (Figma D1/D2/D3).
    private var sheetFitsContent: Bool {
        mode == .teleport || (mode != .teleport && route.canEdit && route.picker == nil)
    }

    /// Each mode panel has a default and a minimum height (Figma B1/B2, D1–D3, E1/E1.a), in points above the tab bar.
    /// Route is content-sized (D1 339, D8 399, capped at D2 414). Accessibility text sizes fall back to content height.
    private var sheetPreferredHeight: CGFloat? {
        guard !dynamicTypeSize.isAccessibilitySize, (!isResumeState || mode == .teleport) else { return nil }
        switch mode {
        // Expanded teleport is content-sized like the route panel: summary plus at most two favorites.
        case .teleport: return (sheetDetent == .collapsed || isTeleportHoldRecovery) ? 120 : nil
        // Wander simulation has no tab bar, so its panel is content-sized plus the safe area (E2 / E2.a / E4).
        case .joystick: return isWanderRunning ? nil : (sheetDetent == .collapsed ? 96 : 349)
        case .route: return nil
        }
    }

    private var showsBottomBar: Bool {
        route.picker == nil && !showsOperationPanel && !isExecutionMode && !isWanderRunning
    }

    /// Route and wander simulation hide the tab bar; a paused wander keeps it for the resume row (E5).
    private var isWanderRunning: Bool {
        // Changing the place pauses the joystick while planning; keep the running layout (no tab bar).
        isWanderMap && (isWanderReplanning || joystick.isAwaitingNextTarget
            || ![.paused, .suspended, .interrupted].contains(joystick.phase))
    }

    private func beginSearch() {
        cancelSearchPasteConfirmation()
        // On the route tab the search bar searches for the selected field (D5).
        if mode == .route, route.canEdit, route.draft.isManual, route.picker == nil, route.openSelectedPicker() {
            pendingRouteNodeTapID = nil
            searchFocusRequest = UUID()
            return
        }
        // The joystick tab keeps its mode: a searched Pin gets the same Go card without switching tabs.
        if !isWanderMap, canSwitchMode, mode == .route { selectMode(.teleport) }
        showingSearch = true
        searchFocusRequest = UUID()
    }

    private func confirmPastedSearch(_ pastedText: String) {
        cancelSearchPasteConfirmation()
        let query = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        search.updateQuery(query)
        switch search.queryKind {
        case .invalidCoordinate:
            presentSearchPasteWarning("search.pasteInvalidCoordinate")
        case .coordinate:
            guard let place = search.results.first else {
                presentSearchPasteWarning("search.pasteInvalidCoordinate")
                return
            }
            selectSearchPlace(place)
        case .empty:
            return
        case .name:
            if let favorite = matchingFavoritePlace(for: query) {
                selectSearchPlace(favorite)
                return
            }
            searchPasteConfirmationTask = Task { @MainActor in
                while search.isSearching {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard isCurrentPastedSearch(query) else { return }
                }
                guard isCurrentPastedSearch(query), search.queryKind == .name else { return }
                if let place = search.results.first {
                    selectSearchPlace(place)
                } else if search.searchFailed {
                    presentSearchPasteWarning("search.pasteSearchFailed")
                } else {
                    presentSearchPasteWarning("search.pastePlaceNotFound")
                }
                searchPasteConfirmationTask = nil
            }
        }
    }

    private func matchingFavoritePlace(for query: String) -> MapPlace? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.favorites.first { favorite in
            (favorite.label?.localizedCaseInsensitiveContains(query) ?? false)
                || favorite.place.title.localizedCaseInsensitiveContains(query)
                || (favorite.place.address?.localizedCaseInsensitiveContains(query) ?? false)
        }?.place
    }

    private func isCurrentPastedSearch(_ query: String) -> Bool {
        search.query == query && !showingSearch && !showingSettings && !showingRouteList
            && presentedSheet == nil && route.picker == nil
    }

    private func cancelSearchPasteConfirmation() {
        searchPasteConfirmationTask?.cancel()
        searchPasteConfirmationTask = nil
    }

    private func presentSearchPasteWarning(_ key: String) {
        searchPasteWarning = GoFlySearchPasteWarning(localizationKey: key)
        UIAccessibility.post(notification: .announcement, argument: goFlyString(key))
    }

    private func announceServiceError(_ error: DeviceServiceFailure) {
        let message = goFlyString(error.rawValue)
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func handleServiceError(_ error: DeviceServiceFailure?) {
        notices.reopen(.serviceError)
        guard let error else { return }
        announceServiceError(error)
    }

    private func handleRealLocationObservation(_ observation: RealLocationObservation?) {
        let explicitlyRequested = pendingGPSRecenter
        pendingGPSRecenter = false
        service.observeRealLocation(observation)
        guard observation != nil else {
            joystickOrigin.fixUnavailable()
            return
        }
        guard let accepted = service.realLocation else {
            joystickOrigin.fixRejected()
            location.rejectedFix()
            return
        }
        joystickOrigin.fixAccepted(GeoCoordinate(latitude: accepted.latitude, longitude: accepted.longitude))
        // GPS fixes move the camera only for Recenter or the first
        // camera of the session; later fixes never pan or zoom it.
        guard explicitlyRequested || (cameraIntent == nil && service.confirmedSimulatedLocation == nil),
              let coordinate = GeoCoordinate(latitude: accepted.latitude, longitude: accepted.longitude) else { return }
        let headingDegrees: Double? = explicitlyRequested ? 0 : nil
        let intent = GoFlyCameraIntent(coordinate: coordinate, headingDegrees: headingDegrees,
                                       resetsZoom: explicitlyRequested)
        cameraIntent = intent
    }

    private func selectRouteNode(_ id: RouteNodeID) {
        guard route.selectNode(id: id) else { return }
        guard pendingRouteNodeTapID == id else {
            pendingRouteNodeTapID = id
            return
        }
        pendingRouteNodeTapID = nil
        guard route.openSelectedPicker() else { return }
        searchFocusRequest = UUID()
    }

    private var routePickerNavigationBinding: Binding<Bool> {
        Binding(
            get: { route.picker != nil },
            set: { isPresented in
                guard !isPresented, let picker = route.picker else { return }
                route.cancelPicker(id: picker.id)
            }
        )
    }

    private func expandSheet() {
        if mode == .teleport {
            sheetDetent = sheetDetent == .half ? .collapsed : .half
        } else {
            sheetDetent = sheetDetent == .expanded ? .half : .expanded
        }
    }

    /// D6.a: while the end-route dialog is open the pill already reads 停止.
    private var displayedPillStatus: GoFlySessionStatus { movement.status }

    private var pillText: String {
        if mode == .teleport, unconfirmedFailure != nil {
            return goFlyString("status.pill.disconnected")
        }
        // The pill shows only the status, never a place name.
        return goFlyString(displayedPillStatus.textKey)
    }

    private var pillTone: GoFlyStatusTone { displayedPillStatus.tone }

    private var hasFreshRealGPS: Bool {
        service.positionMarker?.source == .gps && service.positionMarker?.freshness == .fresh
    }

    private var displayStatusKey: String {
        if mode == .route, !route.canEdit {
            if route.usesPositionAxis, [.running, .pausing, .paused].contains(route.phase) {
                let prefix = route.roundTripEnabled ? "route.status.roundTrip" : "route.status"
                return "\(prefix).\(route.phase.rawValue).\(route.heading.rawValue)"
            }
            return "route.phase.\(route.phase.rawValue)"
        }
        if joystick.phase != .neutral { return "joystick.phase.\(joystick.phase.rawValue)" }
        switch service.pointState {
        case .sending: return "teleport.moving"
        case .unconfirmed: return "teleport.unconfirmed"
        default: return service.statusKey
        }
    }

    private func visibleViewport(in geometry: GeometryProxy) -> CGRect {
        let top = max(viewportGap, topFrame.maxY + viewportGap)
        let bottom = panelFrame.height > 0 ? panelFrame.minY - viewportGap : geometry.size.height - 92
        return CGRect(x: 16, y: top, width: max(1, geometry.size.width - 32), height: max(1, bottom - top))
    }

    private func sheetMaxHeight(in geometry: GeometryProxy) -> CGFloat {
        if mode == .teleport {
            return sheetAvailableHeight(in: geometry)
        }
        return max(132, geometry.size.height - max(topFrame.maxY, 96) - 96 - 49)
    }

    private func sheetRestingHeight(in geometry: GeometryProxy) -> CGFloat {
        if mode == .teleport {
            switch sheetDetent {
            case .collapsed: return currentCollapsedHeight
            case .half, .expanded:
                return min(sheetAvailableHeight(in: geometry), max(currentCollapsedHeight, bottomContentHeight + 24))
            }
        }
        let available = sheetAvailableHeight(in: geometry)
        let expanded = max(117, min(available * 0.88, sheetMaxHeight(in: geometry)))
        let half = min(expanded, max(116, available * 0.5))
        switch sheetDetent {
        case .collapsed: return currentCollapsedHeight
        case .half: return half
        case .expanded: return expanded
        }
    }

    private func panelMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetRestingHeight(in: geometry) - 12)
    }

    private var minimumMapBand: CGFloat {
        // Two 44 pt map controls (plus spacing) must stay visible above the sheet.
        max(96, activeCandidate == nil ? (route.picker == nil ? 120 : 0)
                                       : candidateHeight * 2 + viewportGap * 2)
    }

    private func contentMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetRestingHeight(in: geometry) - 20)
    }

    private var unconfirmedID: UUID? { service.pointState.unconfirmedID }
    private var unconfirmedFailure: DeviceServiceFailure? { service.pointState.unconfirmedFailure }

    private var showsOperationPanel: Bool {
        false
    }

    private var panelPresentsFailure: Bool {
        if case .failed = service.preparedOperation?.state { return true }
        if route.error != nil, !route.canEdit { return true }
        return showsOperationPanel && unconfirmedFailure != nil
    }

    private func cancelPreparation(_ id: UUID) {
        if service.cancelPreparation(id: id) { notices.dismiss(.serviceError) }
    }

    private func candidatePin(_ candidate: TeleportCandidate) -> some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 4 : 0) {
            if route.picker == nil || isMapPicking { goButton(candidate) }
            pinButton(candidate)
        }
        .frame(width: max(84, goWidth))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            updateMeasuredHeight($0, from: candidateHeight) { candidateHeight = $0 }
        }
    }

    private func goButton(_ candidate: TeleportCandidate) -> some View {
        Button {
            if mode == .route {
                confirmRouteCandidate(candidate)
            } else if isWanderMap {
                confirmWanderDestination(candidate.place)
            } else {
                performGo(candidate)
            }
        } label: {
            Text(goButtonTitle)
                .goFlyFont(GoFlyFont.footnoteEmphasis)
                .padding(.horizontal, 16)
                .frame(minWidth: 44, minHeight: 28)
                .foregroundStyle(GoFlyTextColor.inverse)
                .background(GoFlyStyle.primary, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .goFlySteadyDisabled(isGoButtonDisabled)
        .accessibilityIdentifier("map.candidate.go")
    }

    private var goButtonTitle: String {
        if mode == .route || isWanderMap { return goFlyString("common.confirm") }
        return goFlyString("map.go")
    }

    private var isGoButtonDisabled: Bool {
        if mode == .route { return false }
        if isWanderMap {
            return !wanderSearch.canGo || !joystick.canApplyWanderTarget
        }
        return !search.canGo || !service.canTeleport
    }

    private func pinButton(_ candidate: TeleportCandidate) -> some View {
        Button {
            dismissKeyboard()
            if isWanderMap {
                if let place = activeCandidate?.place { confirmWanderDestination(place) }
            } else if mode == .route {
                activeSearch.select(candidate.place)
                sheetDetent = .collapsed
            } else {
                sheetDetent = .half
            }
        } label: {
            GoFlyPlacePinIcon()
                .frame(width: 44, height: 44, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GoFlyTextColor.primary)
        .accessibilityLabel(goFlyString("search.placeDetails"))
        .accessibilityValue(candidate.place.coordinate.displayText)
        .accessibilityIdentifier("map.candidate.pin")
    }


    /// Move only the callout within the unobscured map. Its leader keeps the exact coordinate visible.
    private func wanderPinOverlay<Content: View>(at anchor: CGPoint, size: CGSize, viewport: CGRect,
                                                avoiding other: CGPoint? = nil,
                                                @ViewBuilder content: () -> Content) -> some View {
        let width = min(size.width, viewport.width)
        let height = min(size.height, viewport.height)
        let centerY = min(max(anchor.y - height / 2, viewport.minY + height / 2), viewport.maxY - height / 2)
        var centerX = min(max(anchor.x, viewport.minX + width / 2), viewport.maxX - width / 2)
        if let other, viewport.contains(other) {
            let otherX = min(max(other.x, viewport.minX + 22), viewport.maxX - 22)
            let otherY = min(max(other.y - 22, viewport.minY + 22), viewport.maxY - 22)
            if abs(centerX - otherX) < (width + 44) / 2,
               abs(centerY - otherY) < (height + 44) / 2 {
                let right = otherX + (width + 44) / 2 + 8
                let left = otherX - (width + 44) / 2 - 8
                centerX = right + width / 2 <= viewport.maxX ? right : max(viewport.minX + width / 2, left)
            }
        }
        let bottom = CGPoint(x: centerX, y: centerY + height / 2)
        return ZStack(alignment: .topLeading) {
            if hypot(bottom.x - anchor.x, bottom.y - anchor.y) > 1 {
                Path { path in path.move(to: anchor); path.addLine(to: bottom) }
                    .stroke(GoFlyStyle.primary, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content().position(x: centerX, y: centerY)
        }
    }

    private func recenter() {
        if let simulated = service.confirmedSimulatedLocation {
            cameraIntent = GoFlyCameraIntent(coordinate: simulated, headingDegrees: 0, resetsZoom: true)
        } else {
            pendingGPSRecenter = true
            location.requestRecenter()
        }
    }

    private var wanderCardPlace: MapPlace? {
        selectedWanderPlace ?? (isWanderMap ? activeCandidate?.place : nil)
    }

    private func wanderLocationCard(for place: MapPlace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GoFlyPlaceDetailsView(
                place: place,
                titleLabel: favorites.favorite(for: place)?.label,
                onDismiss: {
                    selectedWanderPlace = nil
                    if isWanderMap {
                        wanderSearch.resetSelection()
                    }
                },
                embedded: true,
                distanceFrom: service.positionMarker?.coordinate,
                canGo: activeCandidate != nil ? (wanderSearch.canGo && joystick.canApplyWanderTarget) : joystick.canApplyWanderTarget,
                primaryTitleKey: "common.confirm",
                onGo: {
                    if let candidate = activeCandidate {
                        confirmWanderDestination(candidate.place)
                    } else if let wanderTarget = joystick.wanderTarget, wanderTarget.place == place {
                        confirmWanderDestination(place)
                    }
                }
            )
        }
        .accessibilityIdentifier("map.wander.locationCard")
    }

    /// D10 重試: repairs the connection of the interrupted route; on success the route continues from where it stopped.
    private func retryInterruptedRoute() { goFlyRetryInterruptedRoute(route: route, recovery: recovery) }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }


}

private struct GoFlyMapSheet: Identifiable {
    enum Content {
        case favorites
        case details(MapPlace)
    }
    let id = UUID()
    let content: Content
}

private typealias GoFlyMapMode = SessionMapMode

private extension SessionMapMode {
    var localizationKey: String { "mode.\(rawValue)" }
}

/// A compact map notice for a concrete continuation reason. The map decides
/// whether to show it after higher-priority recovery and cold-state notices.
struct GoFlyContinuationNotice: View {
    @ObservedObject var continuation: MovementContinuationController
    var onSettings: () -> Void = { }

    var hasContent: Bool {
        continuation.noticeKey != nil
    }

    var body: some View {
        if let key = continuation.noticeKey {
            GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                message: goFlyString("status.repairGuidance"),
                actionTitle: goFlyString("operation.settings"), onAction: onSettings,
                identifier: "background.notice", actionIdentifier: "background.settings")
        }
    }
}

/// UIKit background time for the session checkpoint save window.
@MainActor
private struct UIKitBackgroundSaveTasks: BackgroundSaveTasks {
    func begin(name: String, expiration: @escaping @MainActor () -> Void) -> Int? {
        let task = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in expiration() }
        }
        return task == .invalid ? nil : task.rawValue
    }
    func end(_ task: Int) { UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: task)) }
}

private struct GoFlyMapSheetsModifier<Details: View, Places: View, Routes: View>: ViewModifier {
    let details: Binding<MapPlace?>
    @ViewBuilder let detailsView: (MapPlace) -> Details
    let placesShown: Bool
    let onDismissPlaces: () -> Void
    private var placesBinding: Binding<Bool> {
        Binding(get: { placesShown }, set: { if !$0 { onDismissPlaces() } })
    }
    private var routesBinding: Binding<Bool> {
        Binding(get: { routesShown }, set: { if !$0 { onDismissRoutes() } })
    }
    @ViewBuilder let places: () -> Places
    let routesShown: Bool
    let onDismissRoutes: () -> Void
    @ViewBuilder let routes: () -> Routes

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: details) { detailsView($0) }
            .navigationDestination(isPresented: placesBinding) { places().goFlyPushedFullScreen() }
            .navigationDestination(isPresented: routesBinding) { routes().goFlyPushedFullScreen() }
    }
}

/// The live scene phase for closures that outlive a view body.
@MainActor
private final class GoFlySceneActivity {
    var isActive = false
}
