import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteRoundTripTests {
    @Test func enablingRoundTripDuringASingleRunLatchesTheAxisWithoutChangingItsPosition() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock, roundTrip: false)
        let before = controller.progress
        #expect(!controller.usesPositionAxis)
        #expect(!controller.canToggleHeading)
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.usesPositionAxis)
        #expect(controller.progress == before)
        #expect(controller.toggleHeading())
        #expect(controller.setRoundTripEnabled(false))
        #expect(controller.usesPositionAxis)
        #expect(controller.heading == .reverse)
        #expect(controller.progress?.committedDistanceMeters == before?.committedDistanceMeters)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(!controller.roundTripEnabled)
        #expect(controller.start())
        #expect(controller.heading == .forward)
        #expect(!controller.usesPositionAxis)
        await wait { await device.waiting }
        #expect(controller.cancel())
        await device.finish(.notSent(.operationCancelled))
        await wait { controller.phase == .editing }
    }

    @Test func runningRouteTakesANewSpeedFromItsNextStep() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock, roundTrip: false)
        let executionID = try #require(controller.intent?.id)
        let before = try #require(controller.progress?.committedDistanceMeters)
        let faster = try #require(RouteSpeed(kilometersPerHour: 50))
        #expect(controller.canSetSpeed)
        #expect(controller.setSpeed(faster))
        #expect(controller.intent?.id == executionID)
        #expect(controller.intent?.speed == faster)
        #expect(controller.draft.speed == faster)
        let route = try #require(controller.intent?.route)
        // The single-trip remaining time follows the new speed at once.
        #expect(controller.progress?.estimatedRemaining
                == .seconds((route.totalDistanceMeters - before) / faster.metersPerSecond))
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        await device.finish(.acknowledged)
        let expected = min(route.totalDistanceMeters, before + faster.metersPerSecond * 0.5)
        await wait { controller.progress?.committedDistanceMeters == expected }

        #expect(controller.pause())
        await wait { controller.phase == .paused }
        let slower = try #require(RouteSpeed(kilometersPerHour: 5))
        #expect(controller.setSpeed(slower))
        let pausedAt = try #require(controller.progress?.committedDistanceMeters)
        #expect(controller.progress?.estimatedRemaining
                == .seconds((route.totalDistanceMeters - pausedAt) / slower.metersPerSecond))
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func positionAxisStaysContinuousAcrossAWaypointInBothDirections() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let middle = GeoCoordinate(latitude: 25.00004, longitude: 121)!, destination = GeoCoordinate(latitude: 25.0001, longitude: 121)!
        let values = [start, middle, destination].map { RouteNodeValue.place(MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0)) }
        let controller = RouteExecutionController(draft: RouteDraft(values: values)!, planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock)
        let route = try #require(controller.intent?.route)
        let step = try #require(controller.intent?.speed.metersPerSecond) * 0.5
        #expect(route.points == [start, middle, destination])
        #expect(route.cumulativeDistancesMeters[1] > step)
        #expect(route.cumulativeDistancesMeters[1] < step * 2)
        #expect(controller.progress?.committedDistanceMeters == step * 2)
        #expect(controller.toggleHeading())
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.coordinates.last == route.coordinate(at: step))
        await device.finish(.acknowledged)
        await wait { controller.progress?.committedDistanceMeters == step }
        #expect(controller.progress?.fraction == step / route.totalDistanceMeters)
        #expect(controller.progress?.estimatedRemaining == .seconds(step / (try #require(controller.intent?.speed.metersPerSecond))))
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test(arguments: [false, true])
    func controlsRejectPreparingAndEveryUnhealthyExecutionState(unknown: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.start())
        await wait { await device.waiting }
        #expect(controller.phase == .preparing)
        #expect(!controller.setRoundTripEnabled(false))
        #expect(!controller.toggleHeading())
        await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        await device.finish(unknown ? .unconfirmed(.serviceUnavailable) : .notSent(.serviceUnavailable))
        await wait { controller.phase == (unknown ? .unknown : .interrupted) }
        #expect(!controller.canSetRoundTrip)
        #expect(!controller.setRoundTripEnabled(false))
        #expect(!controller.toggleHeading())
        #expect(controller.roundTripEnabled)
        if unknown {
            #expect(service.stop())
            await wait { !service.nativeBusy }
        } else {
            #expect(controller.cancel())
            await wait { controller.phase == .editing }
        }
    }

    @Test(arguments: [1, 2])
    func directionChangesBeforeAsyncCalleeEntryRejectOldComputationAndConvergeWithoutCatchup(toggles: Int) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device), commands: EntryHoldingRouteCommands
        commands = EntryHoldingRouteCommands(service: service)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: commands, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock)
        let intent = try #require(controller.intent), before = try #require(controller.progress).committedDistanceMeters
        let step = intent.speed.metersPerSecond * 0.5
        commands.holdNextEntry = true
        clock.advance(by: .milliseconds(500))
        await wait { commands.held }
        for _ in 0..<toggles { #expect(controller.toggleHeading()) }
        #expect(controller.heading == (toggles == 1 ? .reverse : .forward))
        #expect(service.routeControlRevision(executionID: intent.id, lease: intent.lease) != commands.capturedRevision)
        clock.advance(by: .seconds(100))
        #expect(await device.coordinates.count == 3)
        commands.release()
        await wait { clock.sleepingCount == 1 }
        #expect(controller.progress?.committedDistanceMeters == before)
        #expect(await device.coordinates.count == 3)
        let expected = before + (toggles == 1 ? -step : step)
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.coordinates.last == intent.route.coordinate(at: expected))
        await device.finish(.acknowledged)
        await wait { controller.progress?.committedDistanceMeters == expected && clock.sleepingCount == 1 }
        #expect(controller.progress?.activeElapsed == .seconds(102))
        #expect(await device.maxConcurrency == 1)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test(arguments: [false, true])
    func changingDirectionWaitsForTruthFromAnAlreadyEnteredNativeCall(claimed: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock(), service: ServiceController
        service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock)
        let intent = try #require(controller.intent), before = try #require(controller.progress).committedDistanceMeters
        let step = intent.speed.metersPerSecond * 0.5
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        if claimed { #expect(await device.claim()) }
        #expect(controller.toggleHeading())
        #expect(controller.progress?.committedDistanceMeters == before)
        if !claimed { #expect(await device.claim() == false) }
        clock.advance(by: .seconds(50))
        #expect(await device.coordinates.count == 4)
        await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        let actual = before + (claimed ? step : 0)
        #expect(controller.progress?.committedDistanceMeters == actual)
        #expect(controller.heading == .reverse)
        #expect(controller.progress?.estimatedRemaining == .seconds(actual / intent.speed.metersPerSecond))
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.coordinates.last == intent.route.coordinate(at: actual - step))
        await device.finish(.acknowledged)
        await wait { controller.progress?.committedDistanceMeters == actual - step }
        #expect(await device.maxConcurrency == 1)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func pausedDirectionAndDisabledRoundTripKeepTheAxisUntilTheActualStartEndpointCompletes() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock)
        let axis = try #require(controller.progress).committedDistanceMeters
        let route = try #require(controller.intent).route
        #expect(controller.pause())
        await wait { controller.phase == .paused }
        #expect(controller.toggleHeading())
        #expect(controller.setRoundTripEnabled(false))
        #expect(controller.phase == .paused)
        #expect(controller.heading == .reverse)
        #expect(controller.usesPositionAxis)
        #expect(controller.progress?.committedDistanceMeters == axis)
        #expect(controller.currentTargetCoordinate == start)
        #expect(!controller.canToggleHeading)
        clock.advance(by: .seconds(1000))
        #expect(await device.coordinates.count == 3)
        #expect(controller.resume())
        // A resume first rewrites the committed position without a cadence wait.
        #expect(clock.sleepingCount == 0)
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await device.coordinates.last == route.coordinate(at: axis))
        #expect(controller.phase == .running, "Rewriting where the route stands is not an arrival")
        for index in 0..<2 {
            await wait { clock.sleepingCount == 1 }
            clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }; await device.finish(.acknowledged)
            if index == 0 { await wait { clock.sleepingCount == 1 } }
        }
        await wait { controller.phase == .editing }
        #expect(controller.completion?.coordinate == start)
        #expect(controller.progress?.fraction == 0)
        #expect(controller.progress?.activeElapsed == .seconds(2))
        #expect(!controller.roundTripEnabled)
        #expect(controller.usesPositionAxis)
        #expect(service.confirmedSimulatedLocation == start)
    }

    @Test(arguments: [false, true])
    func uncheckingChangesOnlyTerminationAndAnEndpointAlreadyAcknowledgedKeepsItsReturnHeading(afterBounce: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let routeDraft = draft(end: GeoCoordinate(latitude: 25.000001, longitude: 121)!)
        let controller = RouteExecutionController(draft: routeDraft, planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        if afterBounce {
            await device.finish(.acknowledged)
            await wait { controller.heading == .reverse && clock.sleepingCount == 1 }
            #expect(controller.setRoundTripEnabled(false))
            #expect(controller.heading == .reverse)
            clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }
        } else { #expect(controller.setRoundTripEnabled(false)) }
        #expect(await device.claim())
        await device.finish(.acknowledged)
        await wait { controller.phase == .editing }
        #expect(controller.completion?.coordinate == (afterBounce ? start : end(routeDraft)))
        #expect(controller.usesPositionAxis)
        #expect(!controller.roundTripEnabled)
        #expect(await device.coordinates == (afterBounce ? [start, end(routeDraft), start] : [start, end(routeDraft)]))
    }

    @Test func anEndpointAcknowledgementDuringPausingBouncesBeforePublishingThePausedETA() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(end: GeoCoordinate(latitude: 25.000001, longitude: 121)!), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.claim())
        #expect(controller.pause())
        #expect(!controller.toggleHeading())
        #expect(!controller.setRoundTripEnabled(false))
        await device.finish(.acknowledged)
        await wait { controller.phase == .paused }
        #expect(controller.heading == .reverse)
        #expect(controller.progress?.fraction == 1)
        #expect(controller.progress?.estimatedRemaining ?? .zero > .zero)
        #expect(controller.completion == nil)
        #expect(!controller.canToggleHeading)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(controller.roundTripEnabled)
    }

    @Test func anAcceptedDirectionChangeSurvivesAPauseBeforeTheUnclaimedCallActuallyReturns() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft(), planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        try await runToTwoAcknowledgedSteps(controller, device, clock)
        let axis = try #require(controller.progress).committedDistanceMeters
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(controller.toggleHeading())
        #expect(controller.pause())
        await device.finish(.notSent(.operationCancelled))
        await wait { controller.phase == .paused }
        #expect(controller.heading == .reverse)
        #expect(controller.progress?.committedDistanceMeters == axis)
        #expect(controller.resume())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { (controller.progress?.committedDistanceMeters ?? axis) < axis }
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func acknowledgedEndpointsBounceWithoutDuplicateSendsAndFreshSingleRunsResetTheAxis() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let draft = draft(end: GeoCoordinate(latitude: 25.000001, longitude: 121)!)
        let controller = RouteExecutionController(draft: draft, planner: RoundTripPlanner(), commands: service, search: RoundTripSearch(), clock: clock,
            cadence: .milliseconds(500))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.heading == .forward)
        #expect(controller.usesPositionAxis)
        #expect(!controller.canToggleHeading)
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(controller.heading == .forward)
        #expect(controller.progress?.fraction == 0)
        await device.finish(.acknowledged)
        await wait { controller.heading == .reverse && clock.sleepingCount == 1 }
        #expect(controller.progress?.fraction == 1)
        #expect(controller.progress?.estimatedRemaining ?? .zero > .zero)
        #expect(controller.completion == nil)
        #expect(controller.currentTargetCoordinate == start)
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.heading == .forward && clock.sleepingCount == 1 }
        #expect(controller.progress?.fraction == 0)
        #expect(await device.coordinates == [start, end(draft), start])
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(controller.roundTripEnabled)
        #expect(controller.setRoundTripEnabled(false))
        #expect(controller.start())
        #expect(controller.heading == .forward)
        #expect(!controller.usesPositionAxis)
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.completion != nil }
        #expect(controller.completion?.coordinate == end(draft))
        #expect(await device.clears == 0)
    }
    private var start: GeoCoordinate { GeoCoordinate(latitude: 25, longitude: 121)! }
    private func runToTwoAcknowledgedSteps(_ controller: RouteExecutionController, _ device: RouteControlledDevice, _ clock: RouteTestClock, roundTrip: Bool = true) async throws {
        #expect(controller.setRoundTripEnabled(roundTrip))
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        for _ in 0..<2 {
            clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }; await device.finish(.acknowledged)
            await wait { clock.sleepingCount == 1 }
        }
    }
    private func draft(end: GeoCoordinate = GeoCoordinate(latitude: 25.01, longitude: 121)!) -> RouteDraft {
        RouteDraft(values: [.place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))])!
    }
    private func end(_ draft: RouteDraft) -> GeoCoordinate {
        if case .place(let place) = draft.destination!.value { return place.coordinate }; preconditionFailure()
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
private struct RoundTripPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}
private struct RoundTripSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
@MainActor private final class EntryHoldingRouteCommands: RouteCommanding {
    let service: ServiceController
    var holdNextEntry = false
    private var entry: CheckedContinuation<Void, Never>?
    private(set) var capturedRevision: UInt64?
    var held: Bool { entry != nil }
    init(service: ServiceController) { self.service = service }
    var canBeginRoute: Bool { service.canBeginRoute }
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { service.routeEvents }
    var currentRouteOrigin: GeoCoordinate? { service.currentRouteOrigin }
    var routeAdmissionRevision: UInt64 { service.routeAdmissionRevision }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome {
        await service.beginRoute(intent, expectedAdmissionRevision: expectedAdmissionRevision)
    }
    func routeControlRevision(executionID: UUID, lease: MovementTaskLease) -> UInt64? { service.routeControlRevision(executionID: executionID, lease: lease) }
    func reviseRouteControl(executionID: UUID, lease: MovementTaskLease) -> UInt64? { service.reviseRouteControl(executionID: executionID, lease: lease) }
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome {
        if holdNextEntry {
            holdNextEntry = false; capturedRevision = expectedControlRevision
            await withCheckedContinuation { entry = $0 }
        }
        return await service.sendRoutePoint(executionID: executionID, lease: lease, sequence: sequence,
            expectedControlRevision: expectedControlRevision, coordinate: coordinate)
    }
    func release() { entry?.resume(); entry = nil }
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { service.pauseRoute(executionID: executionID, lease: lease) }
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { service.resumeRoute(executionID: executionID, lease: lease) }
    func endRoute(executionID: UUID, lease: MovementTaskLease) { service.endRoute(executionID: executionID, lease: lease) }
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement { await service.waitForRouteIdle(executionID: executionID, lease: lease) }
}
