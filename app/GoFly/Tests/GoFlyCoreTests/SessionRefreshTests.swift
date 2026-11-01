import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct SessionRefreshTests {
    @Test func fiveStatesAreIndependentOfProbeProgress() {
        #expect(SessionDisplayStatus(hasError: false, running: false, paused: false, hasSimulated: false) == .started)
        #expect(SessionDisplayStatus(hasError: false, running: true, paused: false, hasSimulated: true) == .simulating)
        #expect(SessionDisplayStatus(hasError: false, running: false, paused: true, hasSimulated: true) == .paused)
        #expect(SessionDisplayStatus(hasError: false, running: false, paused: false, hasSimulated: true) == .stopped)
        #expect(SessionDisplayStatus(hasError: true, running: true, paused: false, hasSimulated: true) == .error)
    }

    @Test func allStatusErrorSourcesOverrideTheTaskState() {
        let errors = SessionStatusErrors(connection: .reachable, service: .pairingRequired,
            route: .planningFailed, joystick: .originUnavailable, wander: .noCandidate,
            dataErrors: ["favorites.error.writeFailed", "recovery.error.writeFailed"])
        #expect(errors.keys == ["error.pairingRequired",
            "joystick.error.originUnavailable", "joystick.error.noCandidate", "favorites.error.writeFailed", "recovery.error.writeFailed"])
        #expect(SessionDisplayStatus(hasError: !errors.isEmpty, running: true, paused: false, hasSimulated: true) == .error)
        #expect(SessionStatusErrors(connection: .checking, service: .operationCancelled).isEmpty)
        #expect(SessionStatusErrors(connection: .reachable).isEmpty)
    }

    @Test func healthyConnectionIsNotPolledAndPathChangeKeepsLastResultWhileChecking() async throws {
        let f = try fixture()
        #expect(f.service.start())
        await wait { f.service.phase == .ready && !f.service.nativeBusy }
        f.recovery.sceneDidBecomeActive()
        await wait { f.recovery.connectionState == .reachable && !f.recovery.isChecking }
        f.monitorClock.advance(by: .seconds(60))
        await Task.yield()
        #expect(await f.probe.count == 1)
        await f.probe.setHeld(true)
        f.recovery.networkPathDidChange()
        await wait { await f.probe.count == 2 && f.recovery.isChecking }
        #expect(f.recovery.connectionState == .reachable)
        await f.probe.release()
        await wait { !f.recovery.isChecking }
        f.recovery.releaseForInactiveScene()
    }

    @Test(arguments: ["fixed", "route", "wander"])
    func failedSilentRepairWaitsForExplicitRetryThenRebuildsAndContinues(mode: String) async throws {
        let f = try fixture()
        try await start(mode, f)
        let originalLease = try #require(f.service.movementAuthority.snapshot.lease)
        let routeDistance = f.route.progress?.committedDistanceMeters
        let target = f.joystick.wanderTarget
        try await failAndAwaitRetry(f, advance: .seconds(5))
        try await retry(f)
        await wait { await f.device.rebuilds == 2 && !f.recovery.automaticRepairInProgress }
        #expect(f.service.movementAuthority.snapshot.lease == originalLease)
        #expect(f.service.movementConnection != .unavailable)
        #expect(f.service.displayPositionMarker?.freshness == .fresh)
        #expect(f.route.progress?.committedDistanceMeters == routeDistance)
        #expect(f.joystick.wanderTarget == target)
        #expect(mode == "route" ? f.route.phase == .running : mode == "wander" ? f.joystick.phase == .moving : f.hold.phase == .running)
        let operations = await f.device.operations
        let reset = try #require(operations.lastIndex(of: "rebuild"))
        #expect(Array(operations[reset...].prefix(3)) == ["rebuild", "prepare", "point"])
        let count = await f.device.points.count
        await wait { f.clock.sleepingCount > 0 }
        f.clock.advance(by: .seconds(5))
        await wait { await f.device.points.count > count }
        #expect(await f.device.rebuilds == 2)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test(arguments: ["fixed", "route", "wander"])
    func runningTaskFailureRepairsSilentlyOnceAndContinuesWithoutRetry(mode: String) async throws {
        let f = try fixture()
        try await start(mode, f)
        let originalLease = try #require(f.service.movementAuthority.snapshot.lease)
        await f.device.failNextPoint()
        f.clock.advance(by: .seconds(5))
        await wait { await f.device.rebuilds == 1 && !f.recovery.automaticRepairInProgress && !f.service.nativeBusy }
        #expect(!f.recovery.isSilentRepairInProgress)
        #expect(!f.recovery.canRetryAutomaticRepair)
        #expect(f.recovery.noticeKey == nil)
        #expect(f.service.movementAuthority.snapshot.lease == originalLease)
        #expect(f.service.movementConnection == .available)
        #expect(mode == "route" ? f.route.phase == .running : mode == "wander" ? f.joystick.phase == .moving : f.hold.phase == .running)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test(arguments: ["fixed", "route", "wander"])
    func ordinaryPendingPointKeepsDisplayStableWithoutInventingACK(mode: String) async throws {
        let f = try fixture()
        try await start(mode, f)
        let previous = f.service.displayPositionMarker
        await f.device.holdNextPoint()
        f.clock.advance(by: .seconds(5))
        await wait { await f.device.pointHeld }
        #expect(f.service.positionMarker?.freshness == .waiting)
        #expect(f.service.displayPositionMarker == previous)
        await f.device.releasePoint()
        await wait { !f.service.nativeBusy && f.service.positionMarker?.freshness == .fresh }
        #expect(f.service.positionMarker?.freshness == .fresh)
        #expect(f.service.stopSimulation())
    }

    @Test(arguments: ["fixed", "route", "wander"])
    func failedProbeLeavesARunningTaskToItsNextWrite(mode: String) async throws {
        let f = try fixture()
        try await start(mode, f)
        f.recovery.sceneDidBecomeActive()
        await wait { !f.recovery.isChecking }
        await f.probe.setFailure(.unavailable)
        f.recovery.networkPathDidChange()
        await wait { !f.recovery.isChecking && f.recovery.connectionState == .unavailable }
        #expect(f.service.movementConnection != .unavailable)
        #expect(!f.service.isRecoveringConnection)
        #expect(!f.recovery.canRetryAutomaticRepair)
        #expect(mode == "route" ? f.route.phase == .running : mode == "wander" ? f.joystick.phase == .moving : f.hold.phase == .running)
        await wait { !f.service.nativeBusy && f.clock.sleepingCount > 0 }
        let count = await f.device.points.count
        f.clock.advance(by: .seconds(5))
        await wait { await f.device.points.count > count }
        #expect(await f.device.rebuilds == 0)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func cancelledRouteLeavesItsLastPositionToAHoldWithAFreshLease() async throws {
        let f = try fixture()
        try await start("route", f)
        let routeLease = try #require(f.service.movementAuthority.snapshot.lease)
        let last = try #require(f.service.unclearedSimulatedCoordinate)
        #expect(f.route.cancel())
        await wait { f.hold.phase == .running && !f.service.nativeBusy }
        #expect(f.hold.intent?.fixedPosition == last)
        #expect(f.hold.intent?.lease != routeLease)
        #expect(f.service.movementAuthority.snapshot.lease == f.hold.intent?.lease)
        #expect(await f.device.points.last == last)
        #expect(await f.device.clears == 0)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func stopDoesNotLeaveAHoldBehind() async throws {
        let f = try fixture()
        try await start("route", f)
        #expect(f.service.stopSimulation())
        await wait { !f.service.nativeBusy && f.route.phase == .editing }
        for _ in 0..<20 { await Task.yield() }
        #expect(f.hold.phase == .idle)
        #expect(f.service.movementAuthority.snapshot.lease == nil)
        f.recovery.releaseForInactiveScene()
    }

    @Test func pausedRouteResendsItsHeldPositionWithoutResuming() async throws {
        let f = try fixture()
        try await start("route", f)
        #expect(f.route.pause())
        await wait { f.route.phase == .paused && !f.service.nativeBusy }
        let lease = f.service.movementAuthority.snapshot.lease
        let held = try #require(f.service.unclearedSimulatedCoordinate)
        let keepAlive = PositionKeepAlive(service: f.service, clock: f.clock, interval: .seconds(15))
        keepAlive.sceneDidBecomeActive()
        let count = await f.device.points.count
        await wait { f.clock.sleepingCount > 0 }
        f.clock.advance(by: .seconds(15))
        await wait { await f.device.points.count == count + 1 }
        #expect(await f.device.points.last == held)
        #expect(f.route.phase == .paused)
        #expect(f.service.movementAuthority.snapshot.lease == lease)
        #expect(f.service.movementAuthority.snapshot.runState == .paused)

        #expect(f.service.stopSimulation())
        await wait { !f.service.nativeBusy }
        let afterStop = await f.device.points.count
        f.clock.advance(by: .seconds(15))
        for _ in 0..<20 { await Task.yield() }
        #expect(await f.device.points.count == afterStop, "Stop ends the heartbeat")
        keepAlive.releaseForInactiveScene()
        f.recovery.releaseForInactiveScene()
    }

    @Test func routeSendsOnePointPerSecondCoveringOneSecondOfDistance() async throws {
        let f = try fixture()
        try await start("route", f)
        let before = try #require(f.route.progress?.committedDistanceMeters)
        let speed = try #require(f.route.intent?.speed.metersPerSecond)
        let count = await f.device.points.count
        f.clock.advance(by: .milliseconds(500))
        for _ in 0..<20 { await Task.yield() }
        #expect(await f.device.points.count == count)
        f.clock.advance(by: .milliseconds(500))
        await wait { await f.device.points.count == count + 1 && !f.service.nativeBusy }
        await wait { (f.route.progress?.committedDistanceMeters ?? 0) > before }
        #expect(abs((f.route.progress?.committedDistanceMeters ?? 0) - before - speed) < 1e-6)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func pausedRouteKeepaliveResumesAfterABackgroundTripAndReverifiesTheArrow() async throws {
        let f = try fixture()
        try await start("route", f)
        #expect(f.route.pause())
        await wait { f.route.phase == .paused && !f.service.nativeBusy }
        f.service.setMovementSceneActive(false)
        f.recovery.releaseForInactiveScene()
        f.service.markSimulationPositionUnverified()
        #expect(f.service.positionMarker?.freshness != .fresh)
        f.service.setMovementSceneActive(true)
        let keepAlive = PositionKeepAlive(service: f.service, clock: f.clock, interval: .seconds(15))
        keepAlive.sceneDidBecomeActive()
        let count = await f.device.points.count
        await wait { f.clock.sleepingCount > 0 }
        f.clock.advance(by: .seconds(15))
        await wait { await f.device.points.count == count + 1 && !f.service.nativeBusy }
        await wait { f.service.positionMarker?.freshness == .fresh }
        #expect(f.route.phase == .paused)
        keepAlive.releaseForInactiveScene()
        #expect(f.service.stopSimulation())
    }

    @Test func settingsStopLeavesNoKeepaliveTarget() async throws {
        let f = try fixture()
        try await start("route", f)
        #expect(f.service.stopSimulation())
        await wait { !f.service.nativeBusy }
        #expect(f.service.unclearedSimulatedCoordinate == nil)
        #expect(f.service.keepAliveTarget == nil)
    }

    @Test func userPauseDuringRebuildKeepsRoutePaused() async throws {
        let f = try fixture()
        try await start("route", f)
        try await failAndAwaitRetry(f, advance: .seconds(1))
        await f.device.setHoldRebuild()
        try await retry(f)
        await wait { await f.device.rebuilds == 2 }
        #expect(f.route.pause())
        await f.device.releaseRebuild()
        await wait { !f.recovery.automaticRepairInProgress }
        #expect(f.route.phase == .paused)
        let count = await f.device.points.count
        f.clock.advance(by: .seconds(10))
        for _ in 0..<20 { await Task.yield() }
        #expect(await f.device.points.count == count)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func failedExplicitRebuildRetainsTaskForAnotherRetryWithoutAutomaticResets() async throws {
        let f = try fixture()
        try await start("route", f)
        let intent = f.route.intent
        try await failAndAwaitRetry(f, advance: .seconds(1))
        await f.device.failNextRebuild()
        try await retry(f)
        await wait { await f.device.rebuilds == 2 && f.recovery.canRetryAutomaticRepair && !f.recovery.automaticRepairInProgress }
        #expect(f.route.intent == intent)
        #expect(f.service.movementConnection == .unavailable)
        f.recovery.networkPathDidChange()
        await wait { !f.recovery.isChecking }
        #expect(await f.device.rebuilds == 2, "probes never repair on their own")
        f.recovery.checkConnection()
        await wait { await f.device.rebuilds == 3 && !f.recovery.automaticRepairInProgress }
        #expect(f.route.phase == .running && f.route.intent == intent)
        #expect(f.service.movementConnection != .unavailable)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test(arguments: ["route", "wander"])
    func pauseAfterFailedWriteStaysPausedThroughRetryAndAllowsExplicitResume(mode: String) async throws {
        let f = try fixture()
        try await start(mode, f)
        try await failAndAwaitRetry(f, advance: .seconds(1))
        #expect(mode == "route" ? f.route.pause() : f.joystick.pause())
        #expect(f.service.movementAuthority.snapshot.runState == .paused)
        try await retry(f)
        await wait { await f.device.rebuilds == 2 && !f.recovery.automaticRepairInProgress }
        #expect(mode == "route" ? f.route.phase == .paused : f.joystick.phase == .paused)
        #expect(f.service.currentJoystickOrigin != nil)
        #expect(mode == "route" ? f.route.resume() : f.joystick.resume())
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func timedOutRebuildCanBeRetriedAfterNativeCallReturns() async throws {
        let watchdog = ManualServiceWatchdog()
        let f = try fixture(watchdog: watchdog)
        try await start("route", f)
        try await failAndAwaitRetry(f, advance: .seconds(1))
        await f.device.setHoldRebuild()
        let priorTimeouts = watchdog.requests.count
        try await retry(f)
        await wait { await f.device.rebuilds == 2 && watchdog.requests.count > priorTimeouts }
        watchdog.fireLatest()
        await wait { f.service.phase == .repairRequired }
        #expect(f.service.nativeBusy)
        await f.device.releaseRebuild()
        await wait { f.recovery.canRetryAutomaticRepair && !f.service.nativeBusy }
        #expect(!f.service.isRecoveringConnection)
        try await retry(f)
        await wait { await f.device.rebuilds == 3 && !f.recovery.automaticRepairInProgress }
        #expect(f.route.phase == .running)
        #expect(f.service.stopSimulation())
        f.recovery.releaseForInactiveScene()
    }

    @Test func backgroundFailureSilentRepairRunsOnceAndItsFailureWaitsForForegroundRetry() async throws {
        let f = try fixture()
        try await start("fixed", f)
        let intent = try #require(f.hold.intent)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(f.service.bindMovementContinuation(grant))
        f.service.setMovementSceneActive(false)
        f.recovery.releaseForInactiveScene(continuingLease: intent.lease)
        f.hold.releaseForInactiveScene(continuingLease: intent.lease)
        try await failAndAwaitRetry(f, advance: .seconds(5))
        #expect(await f.device.rebuilds == 1, "the one silent repair ran in the background and failed")
        #expect(!f.service.movementAuthority.permitsDispatch(for: intent.lease))
        f.service.setMovementSceneActive(true)
        try await retry(f)
        await wait { await f.device.rebuilds == 2 && !f.recovery.automaticRepairInProgress }
        #expect(f.hold.phase == .running)
        #expect(f.service.stopSimulation())
    }

    @Test func userStopDuringRebuildRetainsConnectionWithoutContinuingRoute() async throws {
        let f = try fixture()
        try await start("route", f)
        try await failAndAwaitRetry(f, advance: .seconds(1))
        await f.device.setHoldRebuild()
        try await retry(f)
        await wait { await f.device.rebuilds == 2 }
        #expect(f.service.stopSimulation())
        let points = await f.device.points.count
        await f.device.releaseRebuild()
        await wait { !f.recovery.automaticRepairInProgress && !f.service.nativeBusy }
        #expect(f.route.phase == .editing && f.route.intent == nil)
        #expect(f.service.phase == .ready && f.service.movementConnection != .unavailable)
        #expect(f.service.movementAuthority.snapshot.lease == nil)
        f.clock.advance(by: .seconds(10))
        for _ in 0..<20 { await Task.yield() }
        #expect(await f.device.points.count == points)
        #expect(await f.device.clears == 0)
    }

    @Test func stopSimulationRetainsSessionAndDoesNotClearGPS() async throws {
        let f = try fixture()
        try await start("fixed", f)
        #expect(f.service.stopSimulation())
        await wait { !f.service.nativeBusy }
        #expect(f.service.phase == .ready)
        #expect(f.service.movementAuthority.snapshot.lease == nil)
        #expect(await f.device.clears == 0)
        f.recovery.releaseForInactiveScene()
    }

    private struct Fixture {
        let service: ServiceController
        let route: RouteExecutionController
        let joystick: JoystickMovementController
        let hold: PositionHoldController
        let recovery: ConnectionRecoveryController
        let clock: RouteTestClock
        let monitorClock: RouteTestClock
        let device: RefreshDevice
        let probe: RefreshProbe
    }
    private func fixture(watchdog: ManualServiceWatchdog? = nil) throws -> Fixture {
        let device = RefreshDevice(), clock = RouteTestClock(), monitorClock = RouteTestClock(), probe = RefreshProbe()
        let service = ServiceController(service: device, watchdogSleep: { duration in
            if let watchdog { try await watchdog.sleep(duration) }
            else { try await Task.sleep(for: duration) }
        })
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let draft = RouteDraft(start: .place(place(a)), destination: .place(place(b)))!
        let route = RouteExecutionController(draft: draft, planner: RefreshPlanner(), commands: service, search: RefreshSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let hold = PositionHoldController(service: service, clock: clock, cadence: .seconds(5),
                                          maximumAcknowledgementGap: .seconds(15))
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick, probe: probe, positionHold: hold, clock: monitorClock)
        return Fixture(service: service, route: route, joystick: joystick, hold: hold, recovery: recovery, clock: clock, monitorClock: monitorClock, device: device, probe: probe)
    }
    /// A write failure: the one silent automatic repair rebuilds once and fails
    /// too, so the task stays suspended for an explicit Retry.
    private func failAndAwaitRetry(_ f: Fixture, advance: Duration) async throws {
        let rebuilds = await f.device.rebuilds
        await f.device.failNextRebuild()
        await f.device.failNextPoint()
        f.clock.advance(by: advance)
        await wait { f.recovery.canRetryAutomaticRepair && !f.recovery.automaticRepairInProgress }
        #expect(await f.device.rebuilds == rebuilds + 1)
    }

    private func retry(_ f: Fixture) async throws {
        f.recovery.sceneDidBecomeActive()
        await wait { !f.recovery.isChecking }
        f.recovery.checkConnection()
    }

    private func start(_ mode: String, _ f: Fixture) async throws {
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        if mode == "fixed" {
            #expect(f.service.teleport(to: TeleportCandidate(place: place(coordinate))))
            await wait { f.hold.phase == .running && !f.service.nativeBusy && f.clock.sleepingCount > 0 }
        } else if mode == "route" {
            #expect(f.route.start())
            await wait { f.route.phase == .running && !f.service.nativeBusy && f.clock.sleepingCount > 0 }
        } else {
            f.service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date())!)
            #expect(f.joystick.setWanderEnabled(true))
            await wait { f.joystick.phase == .moving && f.clock.sleepingCount > 0 }
            f.clock.advance(by: .seconds(1))
            await wait { f.joystick.lastAcknowledgedCoordinate != nil && !f.service.nativeBusy && f.clock.sleepingCount > 0 }
        }
    }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: "Refresh", coordinate: coordinate)
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private struct RefreshPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}
private struct RefreshSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor RefreshDevice: DeviceService {
    private(set) var operations: [String] = []
    private(set) var points: [GeoCoordinate] = []
    private(set) var rebuilds = 0
    private(set) var clears = 0
    private var failNext = false
    private var holdNext = false
    private var pointWaiter: CheckedContinuation<Void, Never>?
    var pointHeld: Bool { pointWaiter != nil }
    private var holdRebuild = false
    private var rebuildFails = false
    private var rebuildWaiter: CheckedContinuation<Void, Never>?
    func prepare() async throws { operations.append("prepare") }
    func resetClientConnection() async throws { operations.append("reset") }
    func rebuildClientConnection() async throws {
        rebuilds += 1; operations.append("rebuild")
        if holdRebuild { await withCheckedContinuation { rebuildWaiter = $0 } }
        if rebuildFails { rebuildFails = false; throw DeviceServiceFailure.tunnelUnavailable }
    }
    func clearLocation() async throws { clears += 1 }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        operations.append("point"); points.append(coordinate)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { pointWaiter = $0 }
        }
        if failNext { failNext = false; return .unconfirmed(.tunnelUnavailable) }
        return .acknowledged
    }
    func holdNextPoint() { holdNext = true }
    func releasePoint() { pointWaiter?.resume(); pointWaiter = nil }
    func failNextPoint() { failNext = true }
    func failNextRebuild() { rebuildFails = true }
    func setHoldRebuild() { holdRebuild = true }
    func releaseRebuild() { holdRebuild = false; rebuildWaiter?.resume(); rebuildWaiter = nil }
}
private actor RefreshProbe: TunnelProbing {
    private(set) var count = 0
    private var held = false
    private var failure: TunnelProbeFailure?
    private var waiter: CheckedContinuation<Void, Never>?
    func check() async throws {
        count += 1
        if held { await withCheckedContinuation { waiter = $0 } }
        if let failure { throw failure }
    }
    func setHeld(_ value: Bool) { held = value }
    func setFailure(_ value: TunnelProbeFailure?) { failure = value }
    func release() { waiter?.resume(); waiter = nil }
}
