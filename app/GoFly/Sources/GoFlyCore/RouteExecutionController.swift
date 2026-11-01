import Combine
import Foundation

public enum RouteSuspensionReason: String, Equatable, Sendable {
    case sceneInactive
    case connectionUnavailable
    case backgroundUnavailable
}

private struct RoutePlanningEdge: Hashable {
    let from: GeoCoordinate
    let to: GeoCoordinate
}

private enum RoutePlanningEdgeResult {
    case planned(PlannedRoute)
    case failed
}

/// The repair sheet's state. `total` counts legs of the draft (places - 1).
public enum RoutePlanningRepairState: Equatable, Sendable {
    case running(attempted: Int, total: Int)
    case succeeded(total: Int)
    case failed(succeeded: Int, total: Int, failedPlaces: Int, canDelete: Bool)
}

/// The card shown after pressing Start while the route is planned leg by leg (Figma D24).
public enum RouteStartPlanningState: Equatable, Sendable {
    case planning(done: Int, total: Int)
    case succeeded(total: Int)
    case partial(succeeded: Int, total: Int, failedPlaces: Int, canDelete: Bool)
    case allFailed(total: Int)
}

private struct RouteOrderRepairResult {
    let draft: RouteDraft
    let route: PlannedRoute
    let coordinates: [GeoCoordinate]
}

/// Searches full route permutations in stable order. It plans edges lazily and
/// stops after a fixed request and branch budget, so a large draft cannot
/// trigger a factorial number of Directions requests.
@MainActor
/// Asks for one leg, waiting out Maps throttling instead of failing: a
/// throttled request is asked again after the wait Maps names, for up to a minute.
private func askWaitingOutThrottle(clock: any RouteClock,
                                   _ ask: @Sendable () async throws -> [GeoCoordinate]) async throws -> [GeoCoordinate] {
    var waited: Duration = .zero
    while true {
        do {
            return try await ask()
        } catch let throttled as RoutePlanningThrottled {
            let budget = Duration.seconds(60) - waited
            guard budget > .zero else { throw RouteExecutionFailure.planningFailed }
            let wait = min(max(throttled.retryAfter, .seconds(1)), budget)
            Diagnostics.shared.record("route.planThrottled", category: .movement, level: .notice,
                                      ["wait_s": .number(Double(wait.components.seconds), digits: 0)])
            try await clock.sleep(for: wait)
            waited += wait
        }
    }
}

/// Runs on the main actor with its owner, which hands it the leg cache.
@MainActor
private final class RouteOrderRepairSearch {
    static let maximumExpandedPrefixes = 4_096

    private let planner: any RoutePlanning
    private let nodes: [RouteNode]
    private let coordinates: [GeoCoordinate]
    private let speed: RouteSpeed
    private let clock: any RouteClock
    /// Legs a previous launch planned.
    private let storedLeg: (GeoCoordinate, GeoCoordinate) -> PlannedRoute?
    private(set) var edgeResults: [RoutePlanningEdge: RoutePlanningEdgeResult]
    private var expandedPrefixes = 0
    private var deepestLegs = 0
    /// Reports the most route legs chained so far in one candidate order.
    var onProgress: ((Int) -> Void)?

    init(planner: any RoutePlanning, nodes: [RouteNode], coordinates: [GeoCoordinate],
         speed: RouteSpeed, cachedEdges: [RoutePlanningEdge: RoutePlanningEdgeResult],
         clock: any RouteClock, storedLeg: @escaping (GeoCoordinate, GeoCoordinate) -> PlannedRoute?) {
        self.planner = planner
        self.nodes = nodes
        self.coordinates = coordinates
        self.speed = speed
        self.clock = clock
        self.storedLeg = storedLeg
        edgeResults = cachedEdges
    }

    func findOrder() async -> RouteOrderRepairResult? {
        guard nodes.count >= 2, nodes.count <= RouteDraft.maximumNodeCount,
              nodes.count == coordinates.count else { return nil }
        return await search(order: [], used: Array(repeating: false, count: nodes.count), legs: [])
    }

    private func search(order: [Int], used: [Bool], legs: [PlannedRoute]) async -> RouteOrderRepairResult? {
        guard !Task.isCancelled else { return nil }
        if legs.count > deepestLegs { deepestLegs = legs.count; onProgress?(deepestLegs) }

        if order.count == nodes.count {
            guard let route = try? PlannedRoute(legs: legs, bridgingGaps: true) else { return nil }
            let orderedNodes = order.map { nodes[$0] }
            guard let draft = RouteDraft(nodes: orderedNodes, speed: speed) else { return nil }
            return RouteOrderRepairResult(draft: draft, route: route,
                                          coordinates: order.map { coordinates[$0] })
        }
        guard expandedPrefixes < Self.maximumExpandedPrefixes else { return nil }
        expandedPrefixes += 1

        for next in nodes.indices where !used[next] {
            if Task.isCancelled || expandedPrefixes >= Self.maximumExpandedPrefixes { return nil }

            var nextLegs = legs
            if let previous = order.last {
                // Same rule as the preview: request from the previous road entrance, cache by place pair.
                let from = legs.last?.end ?? coordinates[previous]
                let to = coordinates[next]
                guard coordinates[previous] != to else { continue }
                switch await planEdge(from: from, to: to, cachedAs: RoutePlanningEdge(from: coordinates[previous], to: to)) {
                case .planned(let planned): nextLegs.append(planned)
                case .failed: continue
                case nil: return nil
                }
            }

            var nextUsed = used
            nextUsed[next] = true
            if let result = await search(order: order + [next], used: nextUsed, legs: nextLegs) {
                return result
            }
        }
        return nil
    }

    /// Walks the original order once and reports which legs plan. A place whose leg
    /// fails is skipped, and the next place is tried from the last kept one.
    func analyzeOriginalOrder() async -> (succeeded: Int, failedIndices: [Int])? {
        guard nodes.count >= 2 else { return nil }
        var kept = 0, succeeded = 0
        var failed: [Int] = []
        for index in 1..<nodes.count {
            guard !Task.isCancelled else { return nil }
            let from = coordinates[kept], to = coordinates[index]
            if from == to { succeeded += 1; kept = index; continue }
            switch await planEdge(from: from, to: to, cachedAs: RoutePlanningEdge(from: from, to: to)) {
            case .planned: succeeded += 1; kept = index
            case .failed: failed.append(index)
            case nil: return nil
            }
        }
        return (succeeded, failed)
    }

    private func planEdge(from: GeoCoordinate, to: GeoCoordinate,
                          cachedAs edge: RoutePlanningEdge) async -> RoutePlanningEdgeResult? {
        if let cached = edgeResults[edge] { return cached }
        if let stored = storedLeg(edge.from, edge.to) {
            edgeResults[edge] = .planned(stored)
            return .planned(stored)
        }
        guard !Task.isCancelled else { return nil }
        let planner = planner
        do {
            let points = try await askWaitingOutThrottle(clock: clock) { try await planner.planWalking(from: from, to: to) }
            try Task.checkCancellation()
            let planned = try PlannedRoute(points: points)
            let result = RoutePlanningEdgeResult.planned(planned)
            edgeResults[edge] = result
            return result
        } catch {
            guard !Task.isCancelled else { return nil }
            edgeResults[edge] = .failed
            return .failed
        }
    }
}

@MainActor
public final class RouteExecutionController: ObservableObject {

private func diagnose(_ name: String, category: DiagnosticsCategory, level: DiagnosticsLevel = .debug,
                      _ fields: [String: DiagnosticsField] = [:]) {
    Diagnostics.shared.record(name, category: category, level: level, fields)
}

    @Published public private(set) var draft: RouteDraft
    @Published private var selection: RouteNodeID?
    private var removalUndo: (before: RouteDraft, after: RouteDraft, selection: RouteNodeID?)?
    @Published public private(set) var picker: RoutePickerSession? {
        didSet {
            pickerCandidateSubscription?.cancel()
            pickerCandidateSubscription = picker?.candidates.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    @Published public private(set) var phase: RouteExecutionPhase = .editing
    @Published public private(set) var isRecoveringConnection = false
    @Published public private(set) var intent: RouteExecutionIntent?
    @Published public private(set) var plannedRoute: PlannedRoute?
    @Published public private(set) var isFixingPlanningOrder = false
    @Published public private(set) var repairState: RoutePlanningRepairState?
    @Published public private(set) var startPlanning: RouteStartPlanningState?
    private var failedStartNodeIDs: [RouteNodeID] = []
    private var pendingRepair: (snapshot: RouteDraft, result: RouteOrderRepairResult)?
    private var failedRepairNodeIDs: [RouteNodeID] = []
    @Published public private(set) var progress: RouteProgress?
    @Published public private(set) var error: RouteExecutionFailure?
    @Published public private(set) var completion: RouteCompletion?
    @Published public private(set) var suspensionReason: RouteSuspensionReason?
    @Published public private(set) var roundTripEnabled = false
    @Published public private(set) var usesPositionAxis = false
    @Published public private(set) var loadedFavoriteRecordID: UUID?
    @Published public private(set) var heading: RouteHeading = .forward
    private let planner: any RoutePlanning
    private let commands: any RouteCommanding
    private let search: any PlaceSearching
    private let clock: any RouteClock
    private let cadence: Duration
    private var cadenceSeconds: Double {
        Double(cadence.components.seconds) + Double(cadence.components.attoseconds) / 1e18
    }
    public private(set) var favoriteLoadAdmissionRevision: UInt64 = 0
    private var issuedFavoriteLoadAdmission: UInt64?
    private var issuedImportedLoadAdmission: UInt64?
    /// IDs represent route planner/native transitions that have actually
    /// entered their async body. Completed Task handles do not block a cutline.
    private var physicalOperations: Set<UUID> = []
    private var revision: UInt64 = 0
    private var task: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var planningOrderFixTask: Task<Void, Never>?
    private var previewEdgeResults: [RoutePlanningEdge: RoutePlanningEdgeResult] = [:]
    /// Planned legs kept across launches.
    private let legCache: RouteLegCache
    private var previewInputs: [GeoCoordinate]?
    private var subscription: AnyCancellable?
    private var pickerCandidateSubscription: AnyCancellable?
    private var accumulatedElapsed: Duration = .zero
    private var activeStartedAt: Duration?
    private var sceneActive = true
    private var connectionAvailable = true
    private var recoveryProbePending = false
    private var pendingSuspensionReason: RouteSuspensionReason?
    private let continuationControlSubject = PassthroughSubject<MovementContinuationControlEvent, Never>()
    private let movementAcknowledgementSubject = PassthroughSubject<MovementAcknowledgement, Never>()
    private var continuationIdentity: MovementContinuationIdentity?

    public var continuationControlEvents: AnyPublisher<MovementContinuationControlEvent, Never> {
        continuationControlSubject.eraseToAnyPublisher()
    }

    /// Uses the same ordered road planner as route previews without opening a
    /// second route execution owner or mutating the route draft.
    public func planWanderSegment(from: GeoCoordinate, to: GeoCoordinate) async throws -> PlannedRoute {
        var points = try await planner.plan(from: from, to: to)
        try Task.checkCancellation()
        // Directions start on the nearest road. A wander segment continues the
        // current position, so it first walks from `from` onto that road.
        if let first = points.first, JoystickGeodesy.distanceMeters(from: from, to: first) > 1 {
            points = Array(([from] + points).prefix(10_000))
        }
        return try PlannedRoute(points: points)
    }
    public var movementAcknowledgements: AnyPublisher<MovementAcknowledgement, Never> {
        movementAcknowledgementSubject.eraseToAnyPublisher()
    }

    public init(draft: RouteDraft = RouteDraft(), planner: any RoutePlanning, commands: any RouteCommanding,
                search: any PlaceSearching, clock: any RouteClock = ContinuousRouteClock(),
                cadence: Duration = MovementCadence.path, legCache: RouteLegCache? = nil) {
        self.draft = draft; self.planner = planner; self.commands = commands; self.search = search; self.clock = clock
        self.legCache = legCache ?? RouteLegCache(file: nil)
        self.cadence = cadence
        if let source = draft.gpxSource {
            // A persisted GPX draft is display data. Build only its existing
            // exact preview; do not plan roads or touch the command seam.
            self.plannedRoute = try? PlannedRoute(imported: source.document)
        } else if draft.isManual {
            schedulePreviewPlanning(for: draft)
        }
        subscription = commands.routeEvents.sink { [weak self] event in self?.receive(event) }
    }
    public var canEdit: Bool { phase == .editing }
    public var canStart: Bool { canEdit && sceneActive && connectionAvailable && commands.canBeginRoute && (try? resolvedDraft(draft)) != nil }
    /// The chosen places in route order, the current location resolved when
    /// known: what the map marks while no road has been planned yet.
    public var chosenPlaceCoordinates: [GeoCoordinate] { draft.nodes.compactMap(chosenCoordinate) }
    /// The selected row's position in `chosenPlaceCoordinates`; nil while it is empty.
    public var selectedChosenPlaceIndex: Int? {
        guard let id = selectedNodeID, let index = draft.nodes.firstIndex(where: { $0.id == id }),
              chosenCoordinate(draft.nodes[index]) != nil else { return nil }
        return draft.nodes[..<index].filter { chosenCoordinate($0) != nil }.count
    }
    private func chosenCoordinate(_ node: RouteNode) -> GeoCoordinate? {
        switch node.value {
        case .place(let place): place.coordinate
        case .current: commands.currentRouteOrigin
        case .empty: nil
        }
    }
    public var canAddNode: Bool { canEdit && draft.isManual && draft.nodes.count < RouteDraft.maximumNodeCount }
    public var canClearImportedRoute: Bool { canEdit && draft.gpxSource != nil }
    private func beginPhysicalOperation() -> UUID {
        let id = UUID(); physicalOperations.insert(id); return id
    }
    private func finishPhysicalOperation(_ id: UUID) { physicalOperations.remove(id) }

    /// Capture before asynchronous archive validation; only this outstanding request may replace the draft.
    public func beginFavoriteLoad() -> UInt64? {
        guard canEdit, picker == nil else { return nil }
        invalidateFavoriteLoadAdmission()
        issuedFavoriteLoadAdmission = favoriteLoadAdmissionRevision
        return favoriteLoadAdmissionRevision
    }
    public func beginImportedLoad() -> UInt64? {
        guard canEdit, picker == nil else { return nil }
        invalidateFavoriteLoadAdmission()
        issuedImportedLoadAdmission = favoriteLoadAdmissionRevision
        return favoriteLoadAdmissionRevision
    }
    public func invalidateFavoriteLoadAdmission() {
        favoriteLoadAdmissionRevision &+= 1
        issuedFavoriteLoadAdmission = nil
        issuedImportedLoadAdmission = nil
    }
    @discardableResult public func loadFavoriteRoute(_ snapshot: FavoriteRouteSnapshot, expectedAdmissionRevision: UInt64) -> Bool {
        guard canEdit, picker == nil, issuedFavoriteLoadAdmission == expectedAdmissionRevision,
              favoriteLoadAdmissionRevision == expectedAdmissionRevision else { return false }
        let changed: RouteDraft
        var preview: PlannedRoute?
        switch snapshot.source {
        case .manual(let places):
            guard let manual = RouteDraft(values: places.map { .place($0) }, speed: draft.speed) else { return false }
            changed = manual
        case .gpx(let source):
            do { preview = try PlannedRoute(imported: source.document) }
            catch {
                self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? .invalidPath
                return false
            }
            changed = RouteDraft(gpx: source, speed: draft.speed)
        }
        applyDraft(changed)
        plannedRoute = preview
        loadedFavoriteRecordID = snapshot.record.id
        return true
    }
    @discardableResult public func loadImportedRoute(_ snapshot: ImportedRouteSnapshot,
                                                     expectedAdmissionRevision: UInt64) -> Bool {
        guard canEdit, picker == nil,
              issuedImportedLoadAdmission == expectedAdmissionRevision,
              favoriteLoadAdmissionRevision == expectedAdmissionRevision else { return false }
        let preview: PlannedRoute
        do { preview = try PlannedRoute(imported: snapshot.document) }
        catch {
            self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? .invalidPath
            return false
        }
        applyDraft(RouteDraft(imported: snapshot, speed: draft.speed))
        plannedRoute = preview
        return true
    }
    @discardableResult public func clearImportedRoute() -> Bool {
        guard canClearImportedRoute else { return false }
        applyDraft(RouteDraft(speed: draft.speed))
        return true
    }
    @discardableResult public func clearRoute() -> Bool {
        guard canEdit else { return false }
        applyDraft(RouteDraft(speed: draft.speed))
        return true
    }
    /// The field that D5, the map Pin and the Location Card fill (Figma D1 selected row).
    /// It defaults to the start and falls back to it when the selected row is gone.
    public var selectedNodeID: RouteNodeID? {
        if let selection, draft.nodes.contains(where: { $0.id == selection }) { return selection }
        return draft.start?.id
    }
    /// Selecting a row never opens a picker or changes any value.
    @discardableResult public func selectNode(id: RouteNodeID) -> Bool {
        guard canEdit, picker == nil, draft.nodes.contains(where: { $0.id == id }) else { return false }
        selection = id
        return true
    }
    @discardableResult public func openSelectedPicker() -> Bool {
        guard let id = selectedNodeID else { return false }
        return openPicker(for: id)
    }
    /// Fills only the selected field with a confirmed map or search place.
    @discardableResult public func confirmSelectedNode(with place: MapPlace) -> Bool {
        guard canEdit, draft.isManual, picker == nil, let id = selectedNodeID,
              let changed = draft.replacing(nodeID: id, value: .place(place)) else { return false }
        applyDraft(changed)
        return true
    }
    public var canPause: Bool { phase == .running || isRecoveringConnection }
    public var canSetRoundTrip: Bool { [.editing, .running, .paused].contains(phase) }
    public var canToggleHeading: Bool {
        guard roundTripEnabled, phase == .running || phase == .paused, let intent, let progress else { return false }
        return heading == .forward ? progress.committedDistanceMeters > 0 : progress.committedDistanceMeters < intent.route.totalDistanceMeters
    }
    public var currentTargetCoordinate: GeoCoordinate? {
        guard let intent else { return nil }
        return heading == .forward ? intent.route.end : intent.route.start
    }
    @discardableResult public func setRoundTripEnabled(_ enabled: Bool) -> Bool {
        guard canSetRoundTrip else { return false }
        invalidateFavoriteLoadAdmission()
        roundTripEnabled = enabled
        if enabled, phase == .running || phase == .paused { usesPositionAxis = true }
        if phase == .running, let intent { requestContinuationIfEligible(for: intent) }
        return true
    }
    @discardableResult public func toggleHeading() -> Bool {
        guard canToggleHeading, let intent,
              commands.reviseRouteControl(executionID: intent.id, lease: intent.lease) != nil else { return false }
        heading = heading == .forward ? .reverse : .forward
        publishProgress(distance: progress?.committedDistanceMeters ?? 0, intent: intent)
        if phase == .running { requestContinuationIfEligible(for: intent) }
        return true
    }
    public var canResume: Bool {
        sceneActive && connectionAvailable && !recoveryProbePending && phase == .paused && commands.canBeginRoute
    }

    /// Recovery blocks a paused resume until its fresh probe settles without
    /// interrupting an already running route.
    func recoveryProbeDidStart() { recoveryProbePending = true; objectWillChange.send() }
    func recoveryProbeDidFinish() { recoveryProbePending = false; objectWillChange.send() }
    public var canCancel: Bool {
        [.planning, .preparing, .running, .pausing, .paused, .interrupted].contains(phase)
    }
    @discardableResult public func openPicker(for nodeID: RouteNodeID) -> Bool {
        guard canEdit, let node = draft.nodes.first(where: { $0.id == nodeID }) else { return false }
        invalidateFavoriteLoadAdmission()
        let candidates = CandidateController(search: search)
        if case .place(let place) = node.value { candidates.select(place) }
        picker = RoutePickerSession(id: UUID(), nodeID: nodeID, candidates: candidates,
            allowsCurrent: allowsCurrent, role: draft.role(of: nodeID)!)
        return true
    }
    /// 新增地點: append an empty row as the new destination and select it.
    /// It opens no picker; the person fills it from the search bar, the map or a Pin.
    @discardableResult public func addEmptyWaypoint() -> Bool {
        guard canAddNode, picker == nil else { return false }
        let nodeID = RouteNodeID()
        guard let changed = draft.inserting(nodeID: nodeID, value: .empty) else { return false }
        applyDraft(changed)
        selection = nodeID
        return true
    }
    @discardableResult public func clearPickerPlace(id: UUID) -> Bool {
        guard canEdit, var session = picker, session.id == id else { return false }
        invalidateFavoriteLoadAdmission()
        session.candidates.resetSelection()
        session.clearRevision = session.candidates.editingRevision
        picker = session
        return true
    }
    @discardableResult public func stagePickerCurrent(id: UUID) -> Bool {
        guard canEdit, let session = picker, session.id == id,
              allowsCurrent else { return false }
        invalidateFavoriteLoadAdmission()
        session.candidates.cancelPendingLookups()
        return true
    }
    /// A waypoint row is deleted; the start and destination rows are cleared,
    /// and an empty destination row is deleted (see `RouteDraft.canRemove`).
    @discardableResult public func removeNode(id: RouteNodeID) -> Bool {
        guard canEdit, draft.canRemove(nodeID: id) else { return false }
        let changed: RouteDraft?
        let filled = draft.nodes.filter { $0.value != .empty }.count
        let filledNode = draft.nodes.first(where: { $0.id == id }).map { $0.value != .empty } ?? false
        if case .waypoint? = draft.role(of: id) { changed = draft.removing(nodeID: id) }
        else if !filledNode, draft.role(of: id) == .destination {
            // The previous stop becomes the destination.
            changed = draft.removing(nodeID: id)
        }
        else if filledNode, filled >= 2 {
            // With two or more places the start and destination ✕ delete the place instead of clearing it.
            changed = draft.removing(nodeID: id)
        }
        else { changed = draft.clearing(nodeID: id) ?? draft.removing(nodeID: id) }
        guard let changed else { return false }
        let before = draft, previousSelection = selection
        applyDraft(changed)
        removalUndo = (before, changed, previousSelection)
        return true
    }
    /// D9: only the latest clear or delete can be undone, and only while nothing else changed the route.
    public var canUndoRemoval: Bool {
        guard canEdit, picker == nil, let undo = removalUndo else { return false }
        return draft == undo.after
    }
    @discardableResult public func undoRemoval() -> Bool {
        guard canUndoRemoval, let undo = removalUndo else { return false }
        applyDraft(undo.before)
        selection = undo.selection
        removalUndo = nil
        return true
    }
    /// The moved row becomes the selected field, so the highlight travels with it.
    @discardableResult public func moveNode(id: RouteNodeID, toIndex: Int) -> Bool {
        guard canEdit, let changed = draft.moving(nodeID: id, toIndex: toIndex) else { return false }
        applyDraft(changed)
        if picker == nil { selection = id }
        return true
    }
    @discardableResult public func reverseNodes() -> Bool {
        guard canEdit, let changed = draft.reversing() else { return false }
        applyDraft(changed)
        return true
    }
    @discardableResult public func confirmPicker(id: UUID, useCurrentLocation: Bool = false) -> Bool {
        guard canEdit, draft.isManual, let session = picker, session.id == id else { return false }
        guard draft.nodes.contains(where: { $0.id == session.nodeID }) else { return false }
        if !useCurrentLocation, session.clearedPlace {
            invalidateFavoriteLoadAdmission()
            if !removeNode(id: session.nodeID) { return false }
            picker = nil
            return true
        }
        let value: RouteNodeValue
        if useCurrentLocation {
            guard allowsCurrent else { return false }
            value = .current
        } else {
            guard session.candidates.canGo, let place = session.candidates.candidate?.place else { return false }
            value = .place(place)
        }
        // Only one row can be the current location: choosing it again moves it here.
        var base = draft
        if value == .current {
            for other in draft.nodes where other.id != session.nodeID && other.value == .current {
                guard let cleared = base.clearing(nodeID: other.id) ?? base.removing(nodeID: other.id) else { return false }
                base = cleared
            }
        }
        guard let changed = base.replacing(nodeID: session.nodeID, value: value) else { return false }
        applyDraft(changed)
        picker = nil
        return true
    }
    public func cancelPicker(id: UUID) {
        guard picker?.id == id else { return }
        invalidateFavoriteLoadAdmission()
        picker = nil
    }
    private var allowsCurrent: Bool { draft.isManual }  // D5: offered for every field, whichever row is selected.
    public func setLoadedFavoriteRecordID(_ id: UUID?) {
        loadedFavoriteRecordID = id
    }
    private func applyDraft(_ changed: RouteDraft) {
        invalidateFavoriteLoadAdmission()
        // The map keeps showing the last route and its stops until the new
        // preview replaces it; cleared inputs stop Start from reusing it.
        let shown = changed.isManual ? plannedRoute : nil
        resetPreview()
        loadedFavoriteRecordID = nil
        draft = changed; plannedRoute = shown; completion = nil; error = nil
        guard draft.isManual else { picker = nil; return }
        if var session = picker {
            guard let role = draft.role(of: session.nodeID) else { picker = nil; return }
            session.role = role
            session.allowsCurrent = allowsCurrent
            picker = session
        }
        schedulePreviewPlanning(for: changed)
    }

    /// Reacquires geometry only; never prepares a device or starts movement.
    @discardableResult public func retryPlanning() -> Bool {
        guard canEdit, draft.isManual else { return false }
        resetPreview()
        schedulePreviewPlanning(for: draft)
        return true
    }

    /// Searches a bounded set of full permutations after D8 route planning
    /// fails. It updates only the editable draft and its preview; it never
    /// starts movement or reaches the command owner.
    @discardableResult public func fixPlanningOrder() -> Bool {
        guard canEdit, draft.isManual, error == .planningFailed,
              !isFixingPlanningOrder, !draft.hasEmptyEndpoint,
              draft.nodes.count >= 2, draft.nodes.count <= RouteDraft.maximumNodeCount,
              !draft.nodes.contains(where: { $0.value == .empty }) else { return false }

        var coordinates: [GeoCoordinate] = []
        for node in draft.nodes {
            switch node.value {
            case .current:
                guard let current = commands.currentRouteOrigin else { return false }
                coordinates.append(current)
            case .place(let place): coordinates.append(place.coordinate)
            case .empty: return false
            }
        }

        revision &+= 1
        let token = revision
        let snapshot = draft
        previewTask?.cancel()
        previewTask = nil
        plannedRoute = nil
        previewInputs = nil
        isFixingPlanningOrder = true
        pendingRepair = nil
        failedRepairNodeIDs = []
        repairState = .running(attempted: 0, total: snapshot.nodes.count - 1)
        let search = RouteOrderRepairSearch(planner: planner, nodes: snapshot.nodes,
                                            coordinates: coordinates, speed: snapshot.speed,
                                            cachedEdges: previewEdgeResults, clock: clock,
                                            storedLeg: { [legCache] in legCache.leg(from: $0, to: $1) })
        search.onProgress = { [weak self] attempted in
            guard let self, self.revision == token, self.isFixingPlanningOrder else { return }
            self.repairState = .running(attempted: attempted, total: snapshot.nodes.count - 1)
        }
        planningOrderFixTask = Task { @MainActor [weak self] in
            let result = await search.findOrder()
            let analysis = result == nil ? await search.analyzeOriginalOrder() : nil
            guard let self, self.revision == token, self.draft == snapshot,
                  self.canEdit, !Task.isCancelled else { return }
            self.planningOrderFixTask = nil
            self.isFixingPlanningOrder = false
            // Legs the search planned stay cached, so adopting its order or editing later never repeats them.
            for (edge, edgeResult) in search.edgeResults {
                guard case .planned(let leg) = edgeResult, self.previewEdgeResults[edge] == nil else { continue }
                self.previewEdgeResults[edge] = edgeResult
                self.legCache.store(leg, from: edge.from, to: edge.to)
            }
            if let result {
                // Applied only when the person confirms the sheet.
                self.pendingRepair = (snapshot, result)
                self.repairState = .succeeded(total: snapshot.nodes.count - 1)
                return
            }
            // Leave the original draft and failure toast intact.
            self.error = .planningFailed
            let total = snapshot.nodes.count - 1
            let failedIndices = analysis?.failedIndices ?? []
            self.failedRepairNodeIDs = failedIndices.map { snapshot.nodes[$0].id }
            self.repairState = .failed(succeeded: analysis?.succeeded ?? 0, total: total,
                                       failedPlaces: failedIndices.count,
                                       canDelete: !failedIndices.isEmpty && snapshot.nodes.count - failedIndices.count >= 2)
        }
        return true
    }

    /// 完成: adopts the order the repair found.
    @discardableResult public func confirmPlanningRepair() -> Bool {
        guard canEdit, case .succeeded = repairState, let pending = pendingRepair,
              draft == pending.snapshot else { return false }
        pendingRepair = nil
        repairState = nil
        draft = pending.result.draft
        plannedRoute = pending.result.route
        previewInputs = pending.result.coordinates
        error = nil
        return true
    }

    /// 取消: stops a running repair or dismisses its result, keeping the original order.
    public func cancelPlanningRepair() {
        guard repairState != nil else { return }
        let wasRunning = isFixingPlanningOrder
        planningOrderFixTask?.cancel()
        planningOrderFixTask = nil
        isFixingPlanningOrder = false
        pendingRepair = nil
        failedRepairNodeIDs = []
        repairState = nil
        if wasRunning { revision &+= 1; error = .planningFailed }
    }

    /// 刪除失敗地點: removes the places whose legs could not be planned.
    @discardableResult public func deleteFailedPlanningPlaces() -> Bool {
        guard canEdit, case .failed(_, _, _, let canDelete) = repairState, canDelete else { return false }
        var changed = draft
        for id in failedRepairNodeIDs {
            guard let next = changed.removing(nodeID: id) else { return false }
            changed = next
        }
        failedRepairNodeIDs = []
        applyDraft(changed)
        return true
    }

    private func resetPreview() {
        startPlanning = nil
        failedStartNodeIDs = []
        pendingRepair = nil
        failedRepairNodeIDs = []
        repairState = nil
        revision &+= 1
        previewTask?.cancel()
        previewTask = nil
        planningOrderFixTask?.cancel()
        planningOrderFixTask = nil
        isFixingPlanningOrder = false
        previewInputs = nil
        plannedRoute = nil
        // Planned legs stay valid across edits; failures are retried.
        previewEdgeResults = previewEdgeResults.filter { if case .planned = $0.value { true } else { false } }
        error = nil
    }

    /// Plans the places already chosen. A field still empty, such as a stop
    /// just added, is skipped so the map keeps the route through the others.
    private func schedulePreviewPlanning(for snapshot: RouteDraft) {
        guard canEdit, snapshot.isManual else { return }
        guard let chosen = RouteDraft(nodes: snapshot.nodes.filter { $0.value != .empty }, speed: snapshot.speed),
              chosen.nodes.count >= 2 else { plannedRoute = nil; return }
        let resolved: RouteDraft
        do {
            resolved = try resolvedDraft(chosen)
        } catch {
            plannedRoute = nil
            if let failure = error as? RouteExecutionFailure {
                self.error = failure
            }
            return
        }
        let coordinates = resolved.nodes.compactMap { node -> GeoCoordinate? in
            if case .place(let place) = node.value { return place.coordinate }
            return nil
        }
        guard coordinates.count >= 2 else { return }
        let token = revision
        let planner = self.planner, clock = self.clock
        previewTask = Task { @MainActor [weak self] in
            do {
                var legs: [PlannedRoute] = []
                for index in 1..<coordinates.count {
                    // Requests start at the previous leg's road entrance so the route stays continuous,
                    // while the cache is keyed by the chosen places so an unchanged pair is always reused.
                    let from = legs.last?.end ?? coordinates[0], to = coordinates[index]
                    let edge = RoutePlanningEdge(from: coordinates[index - 1], to: to)
                    guard self?.revision == token, !Task.isCancelled else { return }
                    if case .planned(let cached)? = self?.previewEdgeResults[edge] {
                        legs.append(cached)
                        continue
                    }
                    if let stored = self?.legCache.leg(from: edge.from, to: edge.to) {
                        self?.previewEdgeResults[edge] = .planned(stored)
                        legs.append(stored)
                        continue
                    }
                    let points: [GeoCoordinate]
                    do {
                        points = try await askWaitingOutThrottle(clock: clock) { try await planner.plan(from: from, to: to) }
                    } catch {
                        guard let self, self.revision == token, self.canEdit, !Task.isCancelled else { return }
                        self.previewEdgeResults[edge] = .failed
                        throw error
                    }
                    try Task.checkCancellation()
                    guard let self, self.revision == token, self.canEdit, !Task.isCancelled else { return }
                    do {
                        let planned = try PlannedRoute(points: points)
                        self.previewEdgeResults[edge] = .planned(planned)
                        self.legCache.store(planned, from: edge.from, to: edge.to)
                        legs.append(planned)
                    } catch {
                        self.previewEdgeResults[edge] = .failed
                        throw error
                    }
                }
                guard let self, self.revision == token, self.canEdit, !Task.isCancelled else { return }
                self.plannedRoute = try PlannedRoute(legs: legs, bridgingGaps: true)
                self.previewInputs = coordinates
                self.error = nil
            } catch {
                guard let self, self.revision == token, self.canEdit, !Task.isCancelled else { return }
                self.plannedRoute = nil
                self.error = .planningFailed
            }
        }
    }
    /// Editing changes the draft; a running or paused route also takes the
    /// new speed from its next step, without restarting the execution.
    public var canSetSpeed: Bool { canEdit || [.running, .paused].contains(phase) }
    @discardableResult public func setSpeed(_ speed: RouteSpeed) -> Bool {
        guard canSetSpeed else { return false }
        if canEdit { invalidateFavoriteLoadAdmission() }
        draft = draft.replacing(speed: speed)
        if !canEdit, var current = intent {
            current.speed = speed
            intent = current
            if let progress { publishProgress(distance: progress.committedDistanceMeters, intent: current) }
        }
        return true
    }
    @discardableResult public func start() -> Bool {
        guard canEdit, sceneActive else { return false }
        invalidateFavoriteLoadAdmission()
        guard commands.canBeginRoute else { return false }
        let snapshot: RouteDraft
        do { snapshot = try resolvedDraft(draft) }
        catch {
            self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? (error as? RouteExecutionFailure ?? .invalidPath)
            return false
        }
        let coordinates = snapshot.nodes.compactMap { node -> GeoCoordinate? in
            if case .place(let place) = node.value { return place.coordinate }; return nil
        }
        revision &+= 1
        let token = revision
        let admission = commands.routeAdmissionRevision
        let existingPreview = plannedRoute
        let existingPreviewInputs = previewInputs
        previewTask?.cancel()
        previewTask = nil
        phase = .planning; picker = nil; error = nil; completion = nil; progress = nil; intent = nil
        if snapshot.isManual { plannedRoute = nil }
        accumulatedElapsed = .zero; activeStartedAt = nil
        heading = .forward; usesPositionAxis = roundTripEnabled
        let planner = planner
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            do {
                let route: PlannedRoute
                if let imported = snapshot.gpxSource { route = try PlannedRoute(imported: imported.document) }
                else if let existingPreview, existingPreviewInputs == coordinates {
                    route = existingPreview
                }
                else {
                    var legs: [PlannedRoute] = []
                    var kept = coordinates[0]
                    var failedIndices: [Int] = []
                    let total = coordinates.count - 1
                    let canReportPerPlace = snapshot.nodes.count == coordinates.count
                    await MainActor.run { [weak self] in
                        guard let self, self.revision == token else { return }
                        self.startPlanning = .planning(done: 0, total: total)
                    }
                    for index in 1..<coordinates.count {
                        let from = legs.last?.end ?? kept, to = coordinates[index]
                        do {
                            let points = try await planner.plan(from: from, to: to)
                            guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                            guard self.commands.routeAdmissionRevision == admission else { self.returnToEditing(); return }
                            legs.append(try PlannedRoute(points: points))
                            kept = to
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                            failedIndices.append(index)
                        }
                        guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                        self.startPlanning = .planning(done: index, total: total)
                    }
                    if !failedIndices.isEmpty {
                        guard let self, self.revision == token, self.phase == .planning else { return }
                        self.finishStartPlanningWithFailures(snapshot: snapshot, failedIndices: failedIndices,
                                                             succeeded: legs.count, total: total,
                                                             canReportPerPlace: canReportPerPlace)
                        return
                    }
                    route = try PlannedRoute(legs: legs)
                    await MainActor.run { [weak self] in
                        guard let self, self.revision == token else { return }
                        self.startPlanning = .succeeded(total: total)
                    }
                }
                guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                guard self.commands.routeAdmissionRevision == admission else { self.returnToEditing(); return }
                let intent = RouteExecutionIntent(draft: snapshot, route: route)
                let continuationIdentity = MovementContinuationIdentity(movementID: intent.id, lease: intent.lease)
                self.plannedRoute = route; self.intent = intent; self.phase = .preparing
                self.startPlanning = nil
                self.requestContinuationIfEligible(for: intent)
                let outcome = await self.commands.beginRoute(intent, expectedAdmissionRevision: admission)
                guard self.revision == token, self.phase == .preparing else {
                    if self.continuationIdentity == continuationIdentity {
                        self.withdrawContinuation(.userCancelled)
                    }
                    return
                }
                switch outcome {
                case .acknowledged:
                    self.phase = .running; self.activeStartedAt = self.clock.now
                    self.publishProgress(distance: 0, intent: intent)
                    self.publishRouteAcknowledgement(sequence: 0, distance: 0, position: 0,
                        finiteArrival: false, intent: intent)
                    await self.run(intent, token: token)
                case .cancelled, .controlCancelled:
                    self.withdrawContinuation(.userCancelled)
                    self.returnToEditing()
                case .notSent(let failure):
                    self.withdrawContinuation(.ended)
                    self.phase = .interrupted; self.error = .device(failure)
                case .unconfirmed(let failure):
                    self.withdrawContinuation(.ended)
                    self.phase = .unknown; self.error = .device(failure)
                }
            } catch {
                guard let self, self.revision == token, self.phase == .planning else { return }
                self.withdrawContinuation(.ended)
                self.phase = .editing
                self.startPlanning = nil
                self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? (error as? RouteExecutionFailure ?? .planningFailed)
            }
        }
        return true
    }
    private func resolvedDraft(_ source: RouteDraft) throws -> RouteDraft {
        if let imported = source.gpxSource { _ = try PlannedRoute(imported: imported.document); return source }
        guard !source.nodes.isEmpty, source.start?.value != .empty else { throw RouteExecutionFailure.missingStart }
        guard source.nodes.count >= 2, source.destination?.value != .empty else { throw RouteExecutionFailure.missingDestination }
        let current = source.nodes.contains { $0.value == .current } ? commands.currentRouteOrigin : nil
        guard let resolvedCurrent = source.resolvingCurrent(to: current) else { throw RouteExecutionFailure.currentLocationUnavailable }
        let resolved = resolvedCurrent.mergingConsecutiveDuplicates()
        let coordinates = resolved.nodes.compactMap { node -> GeoCoordinate? in
            if case .place(let place) = node.value { return place.coordinate }; return nil
        }
        guard coordinates.count >= 2, zip(coordinates, coordinates.dropFirst()).allSatisfy({ $0.0 != $0.1 }) else { throw RouteExecutionFailure.invalidPath }
        return resolved
    }
    func suspendForConnectionRecovery() -> Bool {
        if isRecoveringConnection { return true }
        // An interrupted route is retried through the same repair as a running one.
        guard phase == .running || phase == .interrupted else { return false }
        isRecoveringConnection = true
        revision &+= 1
        task?.cancel()
        freezeElapsed()
        phase = .paused
        return true
    }

    func finishConnectionRecovery(succeeded: Bool) {
        guard isRecoveringConnection, let intent else { return }
        isRecoveringConnection = false
        if !succeeded {
            phase = .interrupted; error = .device(.serviceUnavailable)
            withdrawContinuation(.ended)
            return
        }
        phase = .running; error = nil; activeStartedAt = clock.now
        let token = revision
        task = Task { [weak self] in await self?.run(intent, token: token) }
    }

    @discardableResult public func pause() -> Bool {
        if isRecoveringConnection {
            isRecoveringConnection = false
            commands.cancelConnectionRecovery()
            withdrawContinuation(.userPaused)
            phase = .paused
            return true
        }
        let reason = pendingSuspensionReason
        if reason == nil { suspensionReason = nil }
        guard canPause, let intent else { return false }
        guard commands.pauseRoute(executionID: intent.id, lease: intent.lease) else { return false }
        withdrawContinuation(.userPaused)
        phase = .pausing
        let token = revision, running = task
        running?.cancel()
        let physicalID = beginPhysicalOperation()
        transition = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.phase == .pausing else { return }
            self.freezeElapsed()
            switch settlement {
            case .settled:
                self.phase = .paused
                self.suspensionReason = reason
                self.pendingSuspensionReason = nil
            case .requiresStop(let failure): self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    @discardableResult public func resume() -> Bool {
        guard canResume, let intent, commands.resumeRoute(executionID: intent.id, lease: intent.lease) else { return false }
        phase = .running; activeStartedAt = clock.now; suspensionReason = nil
        requestContinuationIfEligible(for: intent)
        let token = revision
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            await self?.run(intent, token: token)
        }
        return true
    }
    @discardableResult public func cancel() -> Bool {
        guard canCancel else { return false }
        if isRecoveringConnection { _ = pause() }
        if phase == .planning {
            revision &+= 1; task?.cancel(); returnToEditing()
            suspensionReason = pendingSuspensionReason
            pendingSuspensionReason = nil
            return true
        }
        guard let intent else { return false }
        let reason = pendingSuspensionReason
        withdrawContinuation(.userCancelled)
        phase = .cancelling
        let token = revision, running = task
        commands.endRoute(executionID: intent.id, lease: intent.lease)
        running?.cancel()
        let physicalID = beginPhysicalOperation()
        transition = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.intent?.id == intent.id,
                  self.phase == .cancelling || self.phase == .unknown else { return }
            switch settlement {
            case .settled:
                self.returnToEditing()
                self.suspensionReason = reason
                self.pendingSuspensionReason = nil
            case .requiresStop(let failure):
                self.freezeElapsed(); self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    public func dismissCompletion(executionID: UUID) {
                if completion?.executionID == executionID { completion = nil }
    }

    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        if isRecoveringConnection, continuingLease != intent?.lease { _ = pause() }
        sceneActive = false
        if let intent, phase == .running, continuingLease == intent.lease {
            objectWillChange.send()
            return
        }
        releaseForUnavailable(reason: .sceneInactive)
    }

    public func sceneDidBecomeActive() {
        sceneActive = true
        objectWillChange.send()
    }

    public func connectionDidBecomeUnavailable() {
        connectionAvailable = false
        releaseForUnavailable(reason: .connectionUnavailable)
    }

    public func connectionDidBecomeAvailable() {
        connectionAvailable = true
        objectWillChange.send()
    }

    public func continuationDidBecomeUnavailable() {
        if isRecoveringConnection { _ = pause() }
        releaseForUnavailable(reason: .backgroundUnavailable)
    }

    private func releaseForUnavailable(reason: RouteSuspensionReason) {
        diagnose("route.suspended", category: .movement, level: .notice, [
            "reason": .text(reason.rawValue),
            "phase": .text(phase.rawValue),
            "progress_m": .number(progress?.committedDistanceMeters ?? 0, digits: 1)
        ])
        switch phase {
        case .running:
            pendingSuspensionReason = reason
            _ = pause()
        case .planning:
            revision &+= 1
            task?.cancel()
            returnToEditing()
            suspensionReason = reason
        case .preparing:
            pendingSuspensionReason = reason
            _ = cancel()
        default:
            break
        }
    }

    private func run(_ intent: RouteExecutionIntent, token: UInt64) async {
        var sequence: UInt64 = 1
        // Resume must continue the service's next sequence, not reuse an old one.
        if let previous = nextSequence[intent.id] { sequence = previous }
        while revision == token, phase == .running {
            do { try await clock.sleep(for: cadence) } catch { return }
            guard revision == token, phase == .running, !Task.isCancelled else { return }
            guard sequence < UInt64.max else {
                continuationDidBecomeUnavailable()
                return
            }
            guard let controlRevision = commands.routeControlRevision(executionID: intent.id, lease: intent.lease) else { return }
            let direction = heading == .forward ? 1.0 : -1.0
            let distance = min(intent.route.totalDistanceMeters, max(0,
                (progress?.committedDistanceMeters ?? 0) + direction * liveSpeed(of: intent).metersPerSecond * cadenceSeconds))
            guard let coordinate = intent.route.coordinate(at: distance) else { phase = .interrupted; error = .invalidPath; return }
            let outcome = await commands.sendRoutePoint(executionID: intent.id, lease: intent.lease,
                sequence: sequence, expectedControlRevision: controlRevision, coordinate: coordinate)
            guard revision == token, self.intent?.id == intent.id, phase == .running || phase == .pausing else { return }
            switch outcome {
            case .acknowledged:
                let previousDistance = progress?.committedDistanceMeters ?? 0
                let delta = abs(distance - previousDistance)
                let atEndpoint = distance == 0 || distance == intent.route.totalDistanceMeters
                // Commit the accepted physical axis before publishing the
                // ACK. Synchronous consumers may change RT at the endpoint;
                // they must compute a zero remaining goal from this actual
                // position while the old heading is still in force.
                publishProgress(distance: distance, intent: intent)
                publishRouteAcknowledgement(sequence: sequence, distance: delta, position: distance,
                    finiteArrival: atEndpoint && !roundTripEnabled, intent: intent)
                sequence += 1; nextSequence[intent.id] = sequence
                if atEndpoint, roundTripEnabled { heading = distance == 0 ? .forward : .reverse }
                if atEndpoint, roundTripEnabled { publishProgress(distance: distance, intent: intent) }
                if atEndpoint, !roundTripEnabled {
                    freezeElapsed()
                    withdrawContinuation(.ended)
                    self.intent = nil; phase = .editing
                    completion = RouteCompletion(executionID: intent.id, coordinate: coordinate)
                    commands.endRoute(executionID: intent.id, lease: intent.lease)
                    nextSequence.removeValue(forKey: intent.id)
                    return
                }
                if phase == .pausing { return }
            case .cancelled: return
            case .controlCancelled: continue
            case .notSent(let failure):
                if phase == .pausing { return }
                diagnose("route.stepFailed", category: .movement, level: .notice, [
                    "seq": .count(Int(truncatingIfNeeded: sequence)),
                    "failure": .text(failure.rawValue),
                    "dispatched": .flag(false),
                    "distance_m": .number(distance, digits: 1)
                ])
                freezeElapsed(); phase = .interrupted; error = .device(failure); return
            case .unconfirmed(let failure):
                diagnose("route.stepUnknown", category: .movement, level: .notice, [
                    "seq": .count(Int(truncatingIfNeeded: sequence)),
                    "failure": .text(failure.rawValue),
                    "distance_m": .number(distance, digits: 1)
                ])
                freezeElapsed(); phase = .unknown; error = .device(failure); return
            }
        }
    }
    private var nextSequence: [UUID: UInt64] = [:]
    private func publishProgress(distance: Double, intent: RouteExecutionIntent) {
        let elapsed = accumulatedElapsed + (activeStartedAt.map { max(.zero, clock.now - $0) } ?? .zero)
        progress = RouteProgress(committedDistanceMeters: distance, totalDistanceMeters: intent.route.totalDistanceMeters,
            activeElapsed: elapsed, estimatedRemaining: .seconds((heading == .forward ? intent.route.totalDistanceMeters - distance : distance)
                / liveSpeed(of: intent).metersPerSecond))
    }
    /// A running route's speed can change; loops hold the intent they started with.
    private func liveSpeed(of intent: RouteExecutionIntent) -> RouteSpeed {
        self.intent?.id == intent.id ? self.intent?.speed ?? intent.speed : intent.speed
    }
    private func freezeElapsed() {
        if let activeStartedAt { accumulatedElapsed += max(.zero, clock.now - activeStartedAt) }
        activeStartedAt = nil
        if let progress {
            self.progress = RouteProgress(committedDistanceMeters: progress.committedDistanceMeters,
                totalDistanceMeters: progress.totalDistanceMeters, activeElapsed: accumulatedElapsed,
                estimatedRemaining: progress.estimatedRemaining)
        }
    }
    private func finishStartPlanningWithFailures(snapshot: RouteDraft, failedIndices: [Int], succeeded: Int,
                                                 total: Int, canReportPerPlace: Bool) {
        returnToEditing()
        error = nil
        failedStartNodeIDs = canReportPerPlace ? failedIndices.map { snapshot.nodes[$0].id } : []
        if succeeded == 0 {
            startPlanning = .allFailed(total: total)
        } else {
            let remaining = draft.nodes.count - failedStartNodeIDs.filter { id in draft.nodes.contains { $0.id == id } }.count
            startPlanning = .partial(succeeded: succeeded, total: total, failedPlaces: failedIndices.count,
                                     canDelete: !failedStartNodeIDs.isEmpty && remaining >= 2)
        }
    }

    /// 取消: stops a running plan or dismisses its result; the draft stays unchanged.
    public func cancelStartPlanning() {
        guard startPlanning != nil else { return }
        if phase == .planning { _ = cancel() }
        failedStartNodeIDs = []
        startPlanning = nil
    }

    /// 刪除失敗地點: removes the places whose legs could not be planned and starts again.
    @discardableResult public func deleteFailedStartPlacesAndStart() -> Bool {
        guard canEdit, case .partial(_, _, _, let canDelete) = startPlanning, canDelete else { return false }
        var changed = draft
        for id in failedStartNodeIDs {
            guard let next = changed.removing(nodeID: id) else { return false }
            changed = next
        }
        applyDraft(changed)
        return start()
    }

    /// 清空地點: every leg failed, so the places are cleared.
    @discardableResult public func clearAfterStartFailure() -> Bool {
        guard canEdit, case .allFailed = startPlanning else { return false }
        return clearRoute()
    }

    private func returnToEditing() {
        freezeElapsed(); phase = .editing
        if let id = intent?.id { nextSequence.removeValue(forKey: id) }
        intent = nil
    }

    private func requestContinuationIfEligible(for intent: RouteExecutionIntent) {
        guard sceneActive else { return }
        diagnose("background.requested", category: .background, level: .notice, [
            "kind": .text(roundTripEnabled ? "roundTrip" : "finiteRoute"),
            "movement": .text(intent.id.uuidString)
        ])
        let current = progress?.committedDistanceMeters ?? 0
        let remaining = heading == .forward
            ? max(0, intent.route.totalDistanceMeters - current)
            : max(0, current)
        let kind: ContinuedProcessingKind = roundTripEnabled ? .roundTrip : .finiteRoute
        let goal: ContinuedProcessingGoal? = roundTripEnabled
            ? .finiteDuration(seconds: BackgroundRunDuration.shared.seconds)
            : (remaining > 0 && remaining.isFinite ? .finiteDistance(meters: remaining) : nil)
        continuationIdentity = MovementContinuationIdentity(movementID: intent.id, lease: intent.lease)
        continuationControlSubject.send(.requested(MovementContinuationDemand(
            movementID: intent.id, lease: intent.lease, kind: kind, goal: goal)))
    }

    private func withdrawContinuation(_ reason: MovementContinuationWithdrawalReason) {
        guard let identity = continuationIdentity else { return }
        diagnose("background.withdrawn", category: .background, level: .notice, [
            "reason": .text(reason.diagnosticsLabel),
            "movement": .text(identity.movementID.uuidString),
            "phase": .text(phase.rawValue)
        ])
        continuationIdentity = nil
        continuationControlSubject.send(.withdrawn(identity, reason))
    }

    private func publishRouteAcknowledgement(sequence: UInt64, distance: Double, position: Double,
                                             finiteArrival: Bool, intent: RouteExecutionIntent) {
        guard distance.isFinite, distance >= 0, position.isFinite, position >= 0 else { return }
        movementAcknowledgementSubject.send(MovementAcknowledgement(
            movementID: intent.id, lease: intent.lease, sequence: sequence, source: .route,
            acknowledgedDistanceMeters: distance, routePositionMeters: position,
            finiteArrival: finiteArrival))
    }

    private func receive(_ event: RouteCommandEvent) {
        switch event {
        case .availabilityChanged:
            if canEdit, error == .currentLocationUnavailable, commands.currentRouteOrigin != nil {
                _ = retryPlanning()
            }
            objectWillChange.send()
        case .ended(let id):
            guard intent?.id == id, phase != .cancelling else { return }
            isRecoveringConnection = false
            withdrawContinuation(.ended)
            revision &+= 1; task?.cancel(); transition?.cancel(); returnToEditing(); error = nil
            nextSequence.removeValue(forKey: id)
        case .interrupted(let id, let failure):
            guard intent?.id == id, phase == .running else { return }
            freezeElapsed(); phase = .interrupted; error = .device(failure); task?.cancel()
        case .unknown(let id, let failure):
            guard intent?.id == id else { return }
            withdrawContinuation(.ended)
            freezeElapsed(); phase = .unknown; error = .device(failure); task?.cancel()
        }
    }
}

@MainActor
public struct RoutePickerSession: Identifiable {
    public let id: UUID
    public let nodeID: RouteNodeID
    public let candidates: CandidateController
    public internal(set) var allowsCurrent: Bool
    public internal(set) var role: RouteNodeRole
    var clearRevision: UInt64?
    public var clearedPlace: Bool {
        guard let clearRevision, clearRevision == candidates.editingRevision else { return false }
        return candidates.candidate == nil && candidates.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
