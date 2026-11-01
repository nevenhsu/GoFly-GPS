import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteEndpointTests {
    @Test func newDraftHasCurrentStartAndEmptyDestination() {
        let draft = RouteDraft()
        #expect(draft.nodes.map(\.value) == [.current, .empty])
        #expect(draft.hasEmptyEndpoint)
    }

    @Test func clearingStartAndDestinationKeepsRowsButWaypointRowsAreDeleted() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)

        #expect(route.removeNode(id: ids[1]))
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2]], "waypoint row is deleted")

        // Two or more places: the start ✕ deletes the place instead of clearing it.
        #expect(route.removeNode(id: ids[0]))
        #expect(route.draft.nodes.map(\.id) == [ids[2]], "start place is deleted")
        // The last remaining place is only cleared.
        #expect(route.removeNode(id: ids[2]))
        #expect(route.draft.nodes.map(\.value) == [.empty])
        #expect(route.draft.nodes.map(\.id) == [ids[2]])
    }

    @Test func movedRowBecomesTheSelectedField() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)
        #expect(route.selectedNodeID == ids[0])

        #expect(route.moveNode(id: ids[0], toIndex: 2))
        #expect(route.draft.nodes.map(\.id) == [ids[1], ids[2], ids[0]])
        #expect(route.selectedNodeID == ids[0], "selection follows the moved row, not the first position")
    }

    @Test func emptyDestinationCanMoveAboveCurrentStart() async throws {
        let route = fixture(draft: RouteDraft())
        let ids = route.draft.nodes.map(\.id)
        #expect(route.moveNode(id: ids[1], toIndex: 0))
        #expect(route.draft.nodes.map(\.id) == [ids[1], ids[0]])
        try await Task.sleep(for: .milliseconds(200))
        #expect(route.draft.nodes.map(\.id) == [ids[1], ids[0]], "no later normalization reverts the move")
    }

    @Test func emptyEndpointDisablesStartAndNeverPlans() async throws {
        let planner = CountingPlanner()
        let draft = try #require(RouteDraft(start: .place(place(1)), destination: .place(place(2))))
        let route = fixture(draft: draft, planner: planner)
        await settle { route.plannedRoute != nil }
        #expect(planner.calls > 0)
        let before = planner.calls

        #expect(route.removeNode(id: draft.nodes[1].id))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!route.canStart)
        #expect(route.plannedRoute == nil)
        #expect(route.error == nil, "an empty endpoint is not a planning error")
        #expect(!route.start())
        #expect(planner.calls == before)
    }

    @Test func addingWaypointAppendsBlankDestinationAndPlansAfterItIsFilled() async throws {
        let planner = CountingPlanner()
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2))]))
        let originalIDs = draft.nodes.map(\.id)
        let route = fixture(draft: draft, planner: planner)
        await settle { route.plannedRoute != nil }
        let callsBeforeAdd = planner.calls

        #expect(route.addEmptyWaypoint())
        let newID = try #require(route.draft.nodes.last?.id)
        #expect(route.draft.nodes.map(\.id) == originalIDs + [newID])
        #expect(route.draft.nodes.map(\.value) == [.place(place(1)), .place(place(2)), .empty])
        #expect(route.draft.role(of: originalIDs[1]) == .waypoint(1))
        #expect(route.draft.role(of: newID) == .destination)
        #expect(route.selectedNodeID == newID)
        #expect(route.draft.hasEmptyEndpoint)
        #expect(route.plannedRoute == nil)
        #expect(route.error == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(planner.calls == callsBeforeAdd, "an empty destination does not trigger preview planning")

        #expect(route.confirmSelectedNode(with: place(3)))
        await settle { route.plannedRoute != nil }
        #expect(planner.calls == callsBeforeAdd + 1, "filling the endpoint plans only the new leg")
        #expect(route.error == nil)
        #expect(route.draft.nodes.map(\.id) == originalIDs + [newID])
    }

    @Test func insertingAStopInTheMiddleOnlyPlansTheTwoChangedLegs() async throws {
        let planner = SnappingPlanner()
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3)), .place(place(4))]))
        let route = fixture(draft: draft, planner: planner)
        await settle { route.plannedRoute != nil }
        #expect(planner.calls == 3)
        let before = planner.calls

        #expect(route.addEmptyWaypoint())
        let newID = try #require(route.draft.nodes.last?.id)
        #expect(route.moveNode(id: newID, toIndex: 1))
        #expect(route.confirmSelectedNode(with: place(5)))
        await settle { route.plannedRoute != nil }
        #expect(route.error == nil)
        #expect(route.draft.nodes.count == 5)
        #expect(planner.calls == before + 2, "only 1→5 and 5→2 are new; 2→3 and 3→4 are reused")
    }

    @Test func appendedWaypointSurvivesRecoveryAndRouteReordering() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let originalIDs = draft.nodes.map(\.id)
        #expect(route.addEmptyWaypoint())
        let newID = try #require(route.draft.nodes.last?.id)
        #expect(route.draft.nodes.map(\.id) == originalIDs + [newID])

        let snapshot = SessionRecoverySnapshot(mode: .route, draft: route.draft)
        let decoded = try SessionRecoveryCodec.decode(SessionRecoveryCodec.encode(snapshot))
        #expect(decoded.draft.nodes.map(\.id) == originalIDs + [newID])
        #expect(decoded.draft.nodes.map(\.value) == draft.nodes.map(\.value) + [.empty])
        #expect(decoded.draft.role(of: originalIDs[2]) == .waypoint(2))
        #expect(decoded.draft.role(of: newID) == .destination)

        #expect(route.reverseNodes())
        #expect(route.draft.nodes.map(\.id) == [newID] + Array(originalIDs.reversed()))
        #expect(route.draft.role(of: newID) == .start)
        #expect(route.moveNode(id: newID, toIndex: route.draft.nodes.count - 1))
        #expect(route.draft.nodes.map(\.id) == Array(originalIDs.reversed()) + [newID])
        #expect(route.draft.role(of: newID) == .destination)
    }

    @Test func addingWaypointIsDisabledAtTheNodeLimit() throws {
        let nodes = (0..<RouteDraft.maximumNodeCount).map { RouteNode(value: .place(place($0))) }
        let draft = try #require(RouteDraft(nodes: nodes))
        let route = fixture(draft: draft)
        #expect(!route.canAddNode)
        #expect(!route.addEmptyWaypoint())
        #expect(route.draft.nodes == nodes)
    }

    @Test func addingWaypointToALoneStartCreatesTheDestinationRow() throws {
        let start = RouteNode(value: .current)
        let draft = try #require(RouteDraft(nodes: [start]))
        let route = fixture(draft: draft)

        #expect(route.addEmptyWaypoint())
        let destination = try #require(route.draft.nodes.last)
        #expect(route.draft.nodes.map(\.id) == [start.id, destination.id])
        #expect(route.draft.role(of: start.id) == .start)
        #expect(route.draft.role(of: destination.id) == .destination)
        #expect(destination.value == .empty)
    }

    @Test func planningFixCanReorderBothNodesIncludingTheOriginalStart() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2))]))
        let originalIDs = draft.nodes.map(\.id)
        let planner = SelectiveRepairPlanner(failingEdges: [EndpointPlannerEdge(
            from: place(1).coordinate, to: place(2).coordinate)])
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await settle { !route.isFixingPlanningOrder }
        #expect(route.repairState == .succeeded(total: draft.nodes.count - 1))
        #expect(route.confirmPlanningRepair())

        #expect(route.error == nil)
        #expect(route.draft.nodes.map(\.id) == Array(originalIDs.reversed()))
        #expect(route.draft.role(of: originalIDs[1]) == .start)
        #expect(route.draft.role(of: originalIDs[0]) == .destination)
        #expect(route.plannedRoute != nil)
    }

    @Test func adoptingTheFixedOrderDoesNotPlanAgainAndKeepsItsLegsCached() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let planner = SelectiveRepairPlanner(failingEdges: [EndpointPlannerEdge(
            from: place(1).coordinate, to: place(2).coordinate)])
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }
        #expect(route.fixPlanningOrder())
        await settle { !route.isFixingPlanningOrder }
        let afterSearch = await planner.callCount

        #expect(route.confirmPlanningRepair())
        try await Task.sleep(for: .milliseconds(100))
        #expect(await planner.callCount == afterSearch, "adopting the result reuses its route")
        #expect(route.plannedRoute != nil)

        // Editing afterwards still reuses the legs the search planned.
        let ids = route.draft.nodes.map(\.id)
        #expect(route.moveNode(id: ids[1], toIndex: 2))
        #expect(route.moveNode(id: ids[1], toIndex: 1))
        await settle { route.plannedRoute != nil }
        #expect(await planner.callCount == afterSearch, "an unchanged order is served from the cache")
    }

    @Test func planningFixFindsAnotherOrderAndPreservesEveryLocation() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let originalIDs = draft.nodes.map(\.id)
        let planner = SelectiveRepairPlanner(failingEdges: [EndpointPlannerEdge(
            from: place(1).coordinate, to: place(2).coordinate)])
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await settle { !route.isFixingPlanningOrder }
        #expect(route.repairState == .succeeded(total: draft.nodes.count - 1))
        #expect(route.confirmPlanningRepair())

        #expect(route.error == nil)
        #expect(route.draft.nodes.map(\.id) == [originalIDs[0], originalIDs[2], originalIDs[1]])
        #expect(route.draft.nodes.count == draft.nodes.count)
        #expect(Set(route.draft.nodes.map(\.id)) == Set(draft.nodes.map(\.id)))
        for node in draft.nodes {
            #expect(route.draft.nodes.first(where: { $0.id == node.id })?.value == node.value)
        }
        #expect(route.plannedRoute != nil)
    }

    @Test func failedPlanningFixLeavesTheDraftAndFailureUntouched() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let planner = SelectiveRepairPlanner(failingAllEdges: true)
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        #expect(route.isFixingPlanningOrder)
        await settle { !route.isFixingPlanningOrder }

        #expect(route.draft == draft)
        #expect(route.error == .planningFailed)
        #expect(route.plannedRoute == nil)
    }

    @Test func failedRepairCountsPlannedLegsAndDeletesTheUnreachablePlace() async throws {
        let draft = try #require(RouteDraft(values: (1...4).map { .place(place($0)) }))
        let ids = draft.nodes.map(\.id)
        let planner = SelectiveRepairPlanner(unreachable: [place(3).coordinate])
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await settle { !route.isFixingPlanningOrder && route.repairState != nil }

        #expect(route.repairState == .failed(succeeded: 2, total: 3, failedPlaces: 1, canDelete: true))
        #expect(route.draft == draft)
        #expect(route.deleteFailedPlanningPlaces())
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[1], ids[3]])
        #expect(route.repairState == nil)
    }

    @Test func startWithAnUnreachablePlaceShowsPartialCardThenDeletesItAndStarts() async throws {
        let draft = try #require(RouteDraft(values: (1...4).map { .place(place($0)) }))
        let ids = draft.nodes.map(\.id)
        let planner = SelectiveRepairPlanner(unreachable: [place(3).coordinate])
        let route = fixture(draft: draft, planner: planner)
        await settle { route.plannedRoute == nil && route.error == .planningFailed || route.plannedRoute != nil }

        #expect(route.start())
        await settle { if case .partial = route.startPlanning { true } else { false } }
        #expect(route.startPlanning == .partial(succeeded: 2, total: 3, failedPlaces: 1, canDelete: true))
        #expect(route.phase == .editing)
        #expect(route.draft == draft)

        #expect(route.deleteFailedStartPlacesAndStart())
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[1], ids[3]])
        #expect(route.startPlanning == nil || route.phase != .editing)
    }

    @Test func startWhereEveryLegFailsOffersToClearThePlaces() async throws {
        let draft = try #require(RouteDraft(values: (1...3).map { .place(place($0)) }))
        let route = fixture(draft: draft, planner: SelectiveRepairPlanner(failingAllEdges: true))
        await settle { route.error == .planningFailed }

        #expect(route.start())
        await settle { if case .allFailed = route.startPlanning { true } else { false } }
        #expect(route.startPlanning == .allFailed(total: 2))
        #expect(route.clearAfterStartFailure())
        #expect(route.startPlanning == nil)
        #expect(route.draft.nodes.allSatisfy { $0.value == .empty || $0.value == .current })
    }

    @Test func cancellingARunningRepairKeepsTheDraftAndFailure() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let planner = HeldRepairPlanner()
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await planner.waitUntilRepairIsHeld()
        if case .running = route.repairState {} else { Issue.record("expected a running repair") }
        route.cancelPlanningRepair()
        await planner.releaseHeldRepair()

        #expect(route.repairState == nil)
        #expect(!route.isFixingPlanningOrder)
        #expect(route.draft == draft)
        #expect(route.error == .planningFailed)
    }

    @Test func planningFixIsBoundedAtTheTwentySevenNodeLimit() async throws {
        let nodes = (0..<RouteDraft.maximumNodeCount).map { RouteNode(value: .place(place($0))) }
        let draft = try #require(RouteDraft(nodes: nodes))
        let planner = SelectiveRepairPlanner(failingAllEdges: true)
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await settle { !route.isFixingPlanningOrder }

        #expect(route.draft == draft)
        #expect(route.error == .planningFailed)
        let calls = await planner.callCount
        // Every directed pair is requested at most once, plus the initial preview and the original-order analysis.
        let count = RouteDraft.maximumNodeCount
        #expect(calls <= count * (count - 1) + 2 * count, "no per-search request cap, but each pair is cached")
    }

    @Test func editingDuringPlanningFixCancelsItsStaleResult() async throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let planner = HeldRepairPlanner()
        let route = fixture(draft: draft, planner: planner)
        await settle { route.error == .planningFailed }

        #expect(route.fixPlanningOrder())
        await planner.waitUntilRepairIsHeld()
        #expect(route.isFixingPlanningOrder)
        #expect(route.reverseNodes())
        #expect(!route.isFixingPlanningOrder)
        await planner.releaseHeldRepair()
        await settle { route.plannedRoute != nil }

        #expect(route.draft.nodes.map(\.id) == Array(draft.nodes.reversed().map(\.id)))
        #expect(route.error == nil)
        #expect(route.plannedRoute != nil)
    }

    @Test func reversingSwapsEmptyValuesWithTheirRows() throws {
        let draft = try #require(RouteDraft(nodes: [RouteNode(value: .place(place(1))), RouteNode(value: .empty)]))
        let reversed = try #require(draft.reversing())
        #expect(reversed.nodes.map(\.value) == [.empty, .place(place(1))])
        #expect(reversed.start?.id == draft.nodes[1].id)
    }

    @Test func emptyEndpointsSurviveRecoveryAndLegacyLoneStartIsPadded() throws {
        let snapshot = SessionRecoverySnapshot(mode: .route, draft: RouteDraft())
        let decoded = try SessionRecoveryCodec.decode(SessionRecoveryCodec.encode(snapshot))
        #expect(decoded.draft.nodes.map(\.value) == [.current, .empty])

        let lone = try #require(RouteDraft(nodes: [RouteNode(value: .current)]))
        let padded = try SessionRecoveryCodec.decode(SessionRecoveryCodec.encode(SessionRecoverySnapshot(mode: .route, draft: lone)))
        #expect(padded.draft.nodes.map(\.value) == [.current, .empty])
    }

    @Test func favoriteSaveSkipsEmptyEndpointsAndNeedsTwoPlaces() throws {
        let draft = try #require(RouteDraft(nodes: [RouteNode(value: .place(place(1))), RouteNode(value: .empty)]))
        #expect(throws: FavoriteRoutesFailure.tooFewValidPlaces) {
            try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        }
    }

    @Test func selectionDefaultsToStartAndOnlyTheSelectedFieldIsFilled() throws {
        let route = fixture(draft: RouteDraft())
        let ids = route.draft.nodes.map(\.id)
        #expect(route.selectedNodeID == ids[0], "new routes select the start")
        #expect(route.selectNode(id: ids[1]))
        #expect(route.picker == nil, "selecting a row never opens a picker")
        #expect(route.draft.nodes.map(\.value) == [.current, .empty])

        #expect(route.confirmSelectedNode(with: place(1)))
        #expect(route.draft.nodes.map(\.value) == [.current, .place(place(1))], "only the destination changes")
        #expect(route.selectedNodeID == ids[1])
        #expect(!route.selectNode(id: RouteNodeID()), "unknown rows cannot be selected")
    }

    @Test func selectionFallsBackToTheStartWhenItsRowDisappears() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)
        #expect(route.selectNode(id: ids[1]))
        #expect(route.removeNode(id: ids[1]))
        #expect(route.selectedNodeID == ids[0])
        #expect(route.clearRoute())
        #expect(route.selectedNodeID == route.draft.start?.id)
    }

    @Test func selectedPickerIsOpenedForTheSelectedFieldOnly() throws {
        let route = fixture(draft: RouteDraft())
        let destination = route.draft.nodes[1].id
        #expect(route.selectNode(id: destination))
        #expect(route.openSelectedPicker())
        #expect(route.picker?.nodeID == destination)
        #expect(route.picker?.role == .destination)
        let session = try #require(route.picker)
        route.cancelPicker(id: session.id)
        #expect(route.draft.nodes[1].value == .empty, "backing out never changes the value")
    }

    @Test func undoRestoresTheOriginalValueAndPosition() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)

        #expect(!route.canUndoRemoval)
        #expect(route.removeNode(id: ids[1]))
        #expect(route.draft.nodes.count == 2 && route.canUndoRemoval)
        #expect(route.undoRemoval())
        #expect(route.draft.nodes.map(\.id) == ids, "the waypoint row returns in its original position")
        #expect(route.draft.nodes.map(\.value) == draft.nodes.map(\.value))
        #expect(!route.canUndoRemoval, "an undo is consumed")

        #expect(route.removeNode(id: ids[0]))
        #expect(route.draft.nodes.map(\.id) == [ids[1], ids[2]], "a start with two or more places is deleted")
        #expect(route.undoRemoval())
        #expect(route.draft.nodes.map(\.id) == ids)
        #expect(route.draft.start?.value == .place(place(1)), "a deleted start gets its place back")
    }

    @Test func onlyTheLatestRemovalCanBeUndone() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3)), .place(place(4))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)
        #expect(route.removeNode(id: ids[1]))
        #expect(route.removeNode(id: ids[2]))
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[3]])
        #expect(route.undoRemoval())
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2], ids[3]], "only the second delete comes back")
        #expect(!route.undoRemoval(), "the earlier delete is not recoverable")
    }

    @Test func undoIsUnavailableAfterAnotherEdit() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        #expect(route.removeNode(id: draft.nodes[1].id))
        #expect(route.reverseNodes())
        #expect(!route.canUndoRemoval)
        #expect(!route.undoRemoval())
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func fixture(draft: RouteDraft, planner: any RoutePlanning = CountingPlanner()) -> RouteExecutionController {
        RouteExecutionController(draft: draft, planner: planner,
                                 commands: ServiceController(service: EndpointDevice()), search: EndpointSearch())
    }

    private func place(_ index: Int) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: 25 + Double(index) * 0.01, longitude: 121)!
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }
}

/// Returns a fixed road entrance for each place, like a provider that snaps a place to its door.
private final class SnappingPlanner: RoutePlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        lock.withLock { count += 1 }
        return [from, GeoCoordinate(latitude: to.latitude + 1e-7, longitude: to.longitude) ?? to]
    }
}

private final class CountingPlanner: RoutePlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        lock.withLock { count += 1 }
        return [from, to]
    }
}

private struct EndpointPlannerEdge: Hashable, Sendable {
    let from: GeoCoordinate
    let to: GeoCoordinate
}

private actor SelectiveRepairPlanner: RoutePlanning {
    private let failingEdges: Set<EndpointPlannerEdge>
    private let failingAllEdges: Bool
    private let unreachable: Set<GeoCoordinate>
    private(set) var callCount = 0

    init(failingEdges: Set<EndpointPlannerEdge> = [], failingAllEdges: Bool = false,
         unreachable: Set<GeoCoordinate> = []) {
        self.failingEdges = failingEdges
        self.failingAllEdges = failingAllEdges
        self.unreachable = unreachable
    }

    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        callCount += 1
        if failingAllEdges || failingEdges.contains(EndpointPlannerEdge(from: from, to: to))
            || unreachable.contains(from) || unreachable.contains(to) {
            throw RouteExecutionFailure.planningFailed
        }
        return [from, to]
    }
}

private actor HeldRepairPlanner: RoutePlanning {
    private var callCount = 0
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var hasHeldRepair = false

    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        callCount += 1
        if callCount == 1 { throw RouteExecutionFailure.planningFailed }
        if callCount == 2 {
            await withCheckedContinuation { continuation in
                heldContinuation = continuation
                hasHeldRepair = true
            }
        }
        return [from, to]
    }

    func waitUntilRepairIsHeld() async {
        for _ in 0..<200 where !hasHeldRepair {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func releaseHeldRepair() {
        heldContinuation?.resume()
        heldContinuation = nil
    }
}

private struct EndpointSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor EndpointDevice: DeviceService {
    func prepare() async throws {}
    func resetClientConnection() async throws {}
    func rebuildClientConnection() async throws {}
    func clearLocation() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}
