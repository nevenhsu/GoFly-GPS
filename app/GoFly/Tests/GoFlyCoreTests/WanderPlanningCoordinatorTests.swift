import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct WanderPlanningCoordinatorTests {
    @Test func startTeleportsToThePlannedStartAndStartsWanderOnItsACK() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let target = WanderTarget(place: place(destination))
        let planner = ScriptedWanderPlanner([.route]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: origin, preselectedTarget: target)
        await wait { host.origin.intentID != nil }
        let intentID = try #require(host.origin.intentID)
        #expect(host.origin.isSetting && wander.isStartOrigin(intentID))
        #expect(planner.calls.count == 1 && planner.calls.first?.to == destination)
        #expect(!joystick.wanderEnabled, "Movement waits for the origin ACK")

        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait {
            if case .acknowledged = service.pointState { return !service.nativeBusy }
            return false
        }
        host.origin = JoystickOriginRequest()
        wander.originAcknowledged(intentID)

        #expect(joystick.wanderEnabled)
        #expect(joystick.wanderTarget == target)
        #expect(host.started.count == 1)
        #expect(!wander.isStartOrigin(intentID))
        #expect(joystick.setWanderEnabled(false))
    }

    @Test func automaticStartPlansToATargetInsideTheWanderRangeAndAnchorsAtItsOrigin() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let planner = ScriptedWanderPlanner([.hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let range = WanderRangeController(radius: WanderRadius(kilometers: 0.1))
        joystick.wanderRange = { [weak range] in range?.range(origin: $0) }
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: origin)
        await wait { planner.isHolding }
        let target = try #require(planner.calls.first?.to)
        #expect(JoystickGeodesy.distanceMeters(from: origin, to: target) <= 100)
        #expect(range.anchor == origin)
        wander.cancelAll()
        planner.release()
    }

    @Test func aResultArrivingAfterCancelAllNeverTeleportsOrFails() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let planner = ScriptedWanderPlanner([.hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: service.currentJoystickOrigin, preselectedTarget: WanderTarget(place: place(destination)))
        await wait { planner.isHolding }
        wander.cancelAll()
        planner.release()
        await settle()

        #expect(service.pointState == .idle)
        #expect(host.origin == JoystickOriginRequest())
        #expect(joystick.wanderError == nil && !joystick.wanderEnabled)
    }

    @Test func everyFailedOriginEndsInOnePlanningFailureThatRetryClears() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let planner = ScriptedWanderPlanner([.fail, .fail, .fail, .hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: service.currentJoystickOrigin, preselectedTarget: WanderTarget(place: place(destination)))
        await wait { joystick.wanderError == .planningFailed }
        #expect(planner.calls.count == 3)

        wander.retryFailedPlanning()
        #expect(joystick.wanderError == nil)
        await wait { planner.calls.count == 4 }
        wander.cancelAll()
        planner.release()
    }

    @Test func startDuringAnInFlightOriginWaitsForThatOriginsOutcome() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let planner = ScriptedWanderPlanner([.hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)
        let originIntent = UUID()
        host.origin = JoystickOriginRequest(isSetting: true, intentID: originIntent)

        wander.start()
        await settle()
        #expect(planner.calls.isEmpty)

        wander.originNotSent(UUID())
        await settle()
        #expect(planner.calls.isEmpty, "Only the matching origin releases the deferred Start")

        host.origin = JoystickOriginRequest()
        wander.originNotSent(originIntent)
        await wait { planner.calls.count == 1 }
        wander.cancelAll()
        planner.release()
    }

    @Test func anUnconfirmedOriginDropsTheDeferredStart() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let planner = ScriptedWanderPlanner([.hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)
        let originIntent = UUID()
        host.origin = JoystickOriginRequest(isSetting: true, intentID: originIntent)

        wander.start()
        host.origin = JoystickOriginRequest()
        wander.originUnconfirmed(originIntent)
        wander.originAcknowledged(originIntent)
        await settle()
        #expect(planner.calls.isEmpty)
    }

    @Test func interruptedStartupResumesWithItsOriginAndTargetOnlyInAnActiveScene() async throws {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let target = WanderTarget(place: place(destination))
        let planner = ScriptedWanderPlanner([.cancellable, .hold]), host = RecordingWanderHost()
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: origin, preselectedTarget: target)
        await wait { planner.calls.count == 1 }
        host.sceneActive = false
        wander.cancelUncommitted()
        await settle()
        #expect(joystick.wanderError == nil)

        wander.resumePending()
        host.recoveryChecking = true
        host.sceneActive = true
        wander.resumePending()
        await settle()
        #expect(planner.calls.count == 1, "Resume waits for an active scene with no recovery check")

        host.recoveryChecking = false
        wander.resumePending()
        await wait { planner.calls.count == 2 }
        #expect(planner.calls[1].from == origin && planner.calls[1].to == target.coordinate)
        wander.cancelAll()
        planner.release()
    }

    @Test func startOutsideJoystickModeDoesNothing() async {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let planner = ScriptedWanderPlanner([.route]), host = RecordingWanderHost()
        host.joystickMode = false
        let joystick = JoystickMovementController(commands: service, clock: RouteTestClock())
        let wander = coordinator(service, joystick, planner, host)

        wander.start(preselectedOrigin: service.currentJoystickOrigin)
        await settle()
        #expect(planner.calls.isEmpty && service.pointState == .idle)
    }

    @Test func aDetachedCoordinatorIsInactive() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let joystick = JoystickMovementController(commands: service)
        let wander = WanderPlanningCoordinator(service: service, joystick: joystick,
                                               origin: JoystickOriginController(service: service, joystick: joystick),
                                               planSegment: { _, _ in throw CancellationError() })
        wander.start()
        #expect(!wander.isReplanning && !wander.hasAcknowledgedPendingStart)
        #expect(joystick.wanderError == nil)
    }

    private let destination = GeoCoordinate(latitude: 25.001, longitude: 121)!

    private func coordinator(_ service: ServiceController, _ joystick: JoystickMovementController,
                             _ planner: ScriptedWanderPlanner, _ host: RecordingWanderHost) -> WanderPlanningCoordinator {
        host.originController = JoystickOriginController(service: service, joystick: joystick)
        let wander = WanderPlanningCoordinator(service: service, joystick: joystick, origin: host.originController,
                                               planSegment: { try await planner.plan(from: $0, to: $1) })
        wander.attach(host.host)
        return wander
    }
    private func location() -> RealLocationObservation { RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date())! }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

/// Plans each call from a script: a straight route, a failure, a hold that
/// ignores cancellation until released, or a hold that cancellation ends.
@MainActor
private final class ScriptedWanderPlanner {
    enum Step { case route, fail, hold, cancellable }
    struct PlanningFailure: Error {}
    private(set) var calls: [(from: GeoCoordinate, to: GeoCoordinate)] = []
    private var steps: [Step]
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }
    init(_ steps: [Step]) { self.steps = steps }

    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> PlannedRoute {
        calls.append((from, to))
        switch steps.isEmpty ? .fail : steps.removeFirst() {
        case .route: break
        case .fail: throw PlanningFailure()
        case .hold: await withCheckedContinuation { held = $0 }
        case .cancellable: try await Task.sleep(for: .seconds(60))
        }
        return try PlannedRoute(points: [from, to])
    }
    func release() { held?.resume(); held = nil }
}

@MainActor
private final class RecordingWanderHost {
    var joystickMode = true
    var sceneActive = true
    var recoveryChecking = false
    var originController: JoystickOriginController!
    var origin: JoystickOriginRequest {
        get { originController.request }
        set { originController.request = newValue }
    }
    var started: [PlannedRoute] = []
    var host: WanderPlanningHost {
        WanderPlanningHost(
            isJoystickMode: { [weak self] in self?.joystickMode ?? false },
            isSceneActive: { [weak self] in self?.sceneActive ?? false },
            isRecoveryChecking: { [weak self] in self?.recoveryChecking ?? false },
            mapOriginCandidates: { [] },
            wanderStarted: { [weak self] in self?.started.append($0) })
    }
}
