import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct PositionHoldControllerTests {
    @Test func pointAcknowledgementStartsOneHoldAtTheExactCoordinateAndEmitsZeroBaseline() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5))
        var acknowledgements: [MovementAcknowledgement] = []
        let subscription = controller.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { subscription.cancel() }
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))

        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        #expect(controller.phase == .idle)
        await device.finishNext(.acknowledged)
        await wait {
            let count = await device.sent.count
            return controller.phase == .preparing && count == 2
        }

        #expect(await device.sent.allSatisfy { $0 == coordinate })
        #expect(acknowledgements.count == 0)
        await device.finishNext(.acknowledged)
        await wait { acknowledgements.count == 1 && clock.sleepingCount > 0 }
        #expect(acknowledgements[0].source == .fixedPosition)
        #expect(acknowledgements[0].sequence == 1)
        #expect(acknowledgements[0].acknowledgedDistanceMeters == 0)
        #expect(acknowledgements[0].cumulativeAcknowledgedDurationSeconds == 0)
        #expect(controller.elapsedSeconds == 0)
    }

    @Test func exactFiniteDurationCompletesAtTheFinalAcknowledgementWithoutAnotherWrite() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5))
        var acknowledgements: [MovementAcknowledgement] = []
        let subscription = controller.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { subscription.cancel() }
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { acknowledgements.count == 1 && clock.sleepingCount > 0 }
        let operation = try #require(controller.intent)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: operation.id, lease: operation.lease)
        #expect(service.bindMovementContinuation(grant))
        service.setMovementSceneActive(false)
        controller.releaseForInactiveScene(continuingLease: operation.lease)

        clock.advance(by: .seconds(5))
        await wait { await device.sent.count == 3 }
        await device.finishNext(.acknowledged)
        await wait { acknowledgements.count == 2 && clock.sleepingCount > 0 }
        #expect(controller.elapsedSeconds == 5)
        #expect(controller.completedCycles == 0)

        clock.advance(by: .seconds(5))
        await wait { await device.sent.count == 4 }
        await device.finishNext(.acknowledged)
        await wait { acknowledgements.count == 3 }
        #expect(controller.elapsedSeconds == 10)
        #expect(controller.completedCycles == 1)
        #expect(controller.phase == .completed)
        #expect(acknowledgements.last?.finiteArrival == true)
        clock.advance(by: .seconds(30))
        #expect(await device.sent.count == 4)
        #expect(await device.sent.allSatisfy { $0 == coordinate })
    }

    @Test func onlyBackgroundTimeCountsAndForegroundReturnResetsWithoutStopping() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount > 0 }

        // Foreground: the hold keeps writing but the countdown does not move.
        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 3 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 3 && clock.sleepingCount > 0 }
        #expect(controller.elapsedSeconds == 0)

        let operation = try #require(controller.intent)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: operation.id, lease: operation.lease)
        #expect(service.bindMovementContinuation(grant))
        service.setMovementSceneActive(false)
        controller.releaseForInactiveScene(continuingLease: operation.lease)
        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 4 }
        await device.finishNext(.acknowledged)
        await wait { controller.elapsedSeconds == 5 && clock.sleepingCount > 0 }

        service.setMovementSceneActive(true)
        controller.sceneDidBecomeActive()
        #expect(controller.elapsedSeconds == 0)
        #expect(controller.phase == .running)
        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 5 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 5 && clock.sleepingCount > 0 }
        #expect(controller.elapsedSeconds == 0)
        #expect(controller.phase == .running)
        #expect(controller.completedCycles == 0)
    }

    @Test func timerCannotAdvanceProgressWithoutAnAcknowledgement() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5), maximumAcknowledgementGap: .seconds(15))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount > 0 }

        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 3 }
        #expect(service.realLocation == nil)
        #expect(service.positionMarker?.freshness == .waiting,
                "A pending fixed-position refresh is not proof that the running hold stopped")
        #expect(service.displayPositionMarker?.freshness == .fresh,
                "Routine pending refresh keeps the last ACK visually stable without changing operation proof")
        clock.advance(by: .seconds(30))
        #expect(controller.elapsedSeconds == 0)
        #expect(controller.completedCycles == 0)
        #expect(controller.phase == .running)
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .paused }
        #expect(controller.elapsedSeconds == 0)
    }

    @Test func LongAckGapPausesAndDiscardsTheOpenInterval() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5), maximumAcknowledgementGap: .seconds(15))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount > 0 }

        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 3 }
        clock.advance(by: .seconds(20))
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .paused }
        #expect(controller.elapsedSeconds == 0)
        #expect(controller.completedCycles == 0)
        #expect(controller.canRetry)
        #expect(controller.pauseCause == .connection, "A missed heartbeat is a connection pause, never the person's")
        let route = RouteExecutionController(planner: StraightPlanner(), commands: service, search: NoPlaceSearch())
        let joystick = JoystickMovementController(commands: service)
        #expect(ActiveMovement(route: route, joystick: joystick, positionHold: controller)
            == ActiveMovement(kind: .positionHold, runState: .paused, pauseCause: .connection,
                              resumeAction: .retryPositionHold, canResume: true))
    }

    @Test func ValidBackgroundGrantContinuesAndExpiryPauses() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount > 0 }
        let operation = try #require(controller.intent)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: operation.id, lease: operation.lease)
        #expect(service.bindMovementContinuation(grant))

        service.setMovementSceneActive(false)
        controller.releaseForInactiveScene(continuingLease: operation.lease)
        clock.advance(by: .seconds(5))
        await wait { (await device.sent.count) == 3 }
        await device.finishNext(.acknowledged)
        await wait { controller.elapsedSeconds == 5 && clock.sleepingCount > 0 }
        #expect(controller.phase == .running)

        grant.revoke()
        clock.advance(by: .seconds(5))
        await wait { controller.phase == .paused }
        #expect(controller.elapsedSeconds == 5)
        #expect(controller.pauseCause == .background)
    }

    @Test func StopAndNativeUnconfirmedResultCannotReviveTheHold() async throws {
        let device = PositionHoldDevice()
        let service = ServiceController(service: device)
        let clock = PositionHoldManualClock()
        let controller = PositionHoldController(service: service, clock: clock)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await device.sent.count == 1 }
        await device.finishNext(.acknowledged)
        await wait { (await device.sent.count) == 2 }
        await device.finishNext(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount > 0 }
        clock.advance(by: .seconds(5))
        await Task.yield()
        #expect(await device.sent.count == 2, "the heartbeat is fifteen seconds")
        clock.advance(by: .seconds(10))
        await wait { (await device.sent.count) == 3 }
        #expect(service.stop())
        await device.finishNext(.acknowledged)
        await wait { !service.nativeBusy }
        #expect(controller.phase == .idle)
        clock.advance(by: .seconds(30))
        #expect(await device.sent.count == 3)

        let secondDevice = PositionHoldDevice()
        let secondService = ServiceController(service: secondDevice)
        let secondClock = PositionHoldManualClock()
        let secondController = PositionHoldController(service: secondService, clock: secondClock)
        #expect(secondService.teleport(to: TeleportCandidate(place: place(coordinate))))
        await wait { await secondDevice.sent.count == 1 }
        await secondDevice.finishNext(.acknowledged)
        await wait { (await secondDevice.sent.count) == 2 }
        await secondDevice.finishNext(.unconfirmed(.serviceUnavailable))
        await wait { secondController.phase == .unknown }
        #expect(!secondController.canRetry)
        secondClock.advance(by: .seconds(30))
        #expect(await secondDevice.sent.count == 2)
    }

    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: "Held", coordinate: coordinate)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private final class PositionHoldManualClock: RouteClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []

    var now: Duration { lock.withLock { instant } }
    var sleepingCount: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let wasCancelled = lock.withLock {
                    if cancelled.remove(id) != nil { return true }
                    sleepers[id] = Sleeper(deadline: instant + duration, continuation: continuation)
                    return false
                }
                if wasCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
                if let sleeper = sleepers.removeValue(forKey: id) { return sleeper.continuation }
                cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock {
            instant += duration
            let ready = sleepers.filter { $0.value.deadline <= instant }
            for id in ready.keys { sleepers.removeValue(forKey: id) }
            return ready.values.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }
}

private actor PositionHoldDevice: DeviceService {
    private var replies: [CheckedContinuation<PointDeliveryOutcome, Never>] = []
    private var queuedFailure: PointDeliveryOutcome?
    private(set) var sent: [GeoCoordinate] = []

    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        sent.append(coordinate)
        if let queuedFailure {
            self.queuedFailure = nil
            return queuedFailure
        }
        return await withCheckedContinuation { replies.append($0) }
    }

    func finishNext(_ outcome: PointDeliveryOutcome) {
        guard !replies.isEmpty else {
            queuedFailure = outcome
            return
        }
        replies.removeFirst().resume(returning: outcome)
    }
}

private struct StraightPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
    func planWalking(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct NoPlaceSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
