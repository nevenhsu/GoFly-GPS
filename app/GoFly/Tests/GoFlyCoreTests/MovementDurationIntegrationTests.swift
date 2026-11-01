import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct MovementDurationIntegrationTests {
    @Test func roundTripFiniteDurationStopsAfterTwelveHoursAndFinishesOnce() async throws {
        let savedDuration = BackgroundRunDuration.shared.seconds
        BackgroundRunDuration.shared.seconds = 43_200
        defer { BackgroundRunDuration.shared.seconds = savedDuration }
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(location(origin))
        let route = RouteExecutionController(draft: routeDraft(origin: origin),
            planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            clock: clock, driver: driver)
        var acknowledgements = 0
        let subscription = route.movementAcknowledgements.sink { _ in acknowledgements += 1 }
        defer { subscription.cancel() }

        #expect(route.setRoundTripEnabled(true))
        #expect(route.start())
        await waitUntil { route.phase == .running && acknowledgements >= 1 && clock.cadenceSleepingCount >= 1 }
        await enterBackground(facade)

        for index in 0..<2_880 {
            clock.advance(by: .seconds(15))
            let expected = index + 2
            await waitUntil {
                guard route.phase == .running else { return index == 2_879 }
                return acknowledgements >= expected && clock.cadenceSleepingCount >= 1
            }
            #expect(route.phase == .running || index == 2_879)
        }
        await waitUntil { route.phase == .paused || route.phase == .editing }
        #expect(route.phase == .paused)
        #expect(facade.state == .finished)
        #expect(driver.submitCount == 1)
        #expect(driver.finishCount == 1)
        let request = try #require(driver.requests.first)
        #expect(request.goal == .finiteDuration(seconds: 43_200))
        let progress = try #require(driver.lastProgress)
        #expect(progress.cumulativeAcknowledgedDurationSeconds == 43_200)

        let writesAtTerminal = await device.moveCount
        for _ in 0..<4 { clock.advance(by: .seconds(15)); await Task.yield() }
        #expect(await device.moveCount == writesAtTerminal)
        #expect(driver.submitCount == 1)
    }

    @Test func foregroundTimeNeverCountsAndReturnRestartsTheCountdown() async throws {
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(location(origin))
        let route = RouteExecutionController(draft: routeDraft(origin: origin),
            planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            clock: clock, driver: driver)
        var acknowledgements = 0
        let subscription = route.movementAcknowledgements.sink { _ in acknowledgements += 1 }
        defer { subscription.cancel() }

        #expect(route.setRoundTripEnabled(true))
        #expect(route.start())
        await waitUntil { route.phase == .running && acknowledgements >= 1 && clock.cadenceSleepingCount >= 1 }
        // More than the 12-hour run time in the foreground: nothing counts, nothing stops.
        for index in 0..<2_881 {
            clock.advance(by: .seconds(15))
            let expected = index + 2
            await waitUntil { acknowledgements >= expected && clock.cadenceSleepingCount >= 1 }
        }
        #expect(route.phase == .running)
        #expect(driver.finishCount == 0)
        #expect((driver.lastProgress?.cumulativeAcknowledgedDurationSeconds ?? 0) == 0)

        await enterBackground(facade)
        for index in 0..<4 {
            clock.advance(by: .seconds(15))
            let expected = 2_883 + index
            await waitUntil { acknowledgements >= expected && clock.cadenceSleepingCount >= 1 }
        }
        #expect(driver.lastProgress?.cumulativeAcknowledgedDurationSeconds == 60)

        // Back in the foreground: the countdown is cancelled and a fresh task
        // waits for the next background trip; the route keeps moving.
        facade.sceneDidBecomeActive()
        await waitUntil { driver.submitCount == 2 && facade.hasRuntime }
        #expect(route.phase == .running)
        #expect(driver.requests.last?.goal == .finiteDuration(seconds: BackgroundRunDuration.shared.seconds))
        clock.advance(by: .seconds(15))
        await waitUntil { acknowledgements >= 2_887 && clock.cadenceSleepingCount >= 1 }
        #expect((driver.lastProgress?.cumulativeAcknowledgedDurationSeconds ?? 0) == 0)
        #expect(route.phase == .running)
    }

    @Test func roundTripWithoutAnSDKGrantKeepsRunningInTheForeground() async throws {
        for scenario in [DurationIntegrationDriver.Scenario.registrationRejected,
                         .submissionRejected] {
            let clock = DurationIntegrationClock()
            let device = DurationIntegrationDevice()
            let service = ServiceController(service: device)
            let origin = GeoCoordinate(latitude: 25, longitude: 121)!
            service.observeRealLocation(location(origin))
            let route = RouteExecutionController(draft: routeDraft(origin: origin),
                planner: DurationIntegrationPlanner(), commands: service,
                search: DurationIntegrationSearch(), clock: clock)
            let joystick = JoystickMovementController(commands: service, clock: clock)
            let driver = DurationIntegrationDriver(scenario: scenario)
            let facade = makeFacade(service: service, route: route, joystick: joystick,
                clock: clock, driver: driver)
            var acknowledgements = 0
            let subscription = route.movementAcknowledgements.sink { _ in acknowledgements += 1 }

            #expect(route.setRoundTripEnabled(true))
            #expect(route.start())
            await waitUntil { route.phase == .running && acknowledgements >= 1 && clock.cadenceSleepingCount >= 1 }
            for index in 0..<2_881 {
                clock.advance(by: .seconds(15))
                let expected = index + 2
                await waitUntil { acknowledgements >= expected && clock.cadenceSleepingCount >= 1 }
            }
            #expect(route.phase == .running)
            #expect(facade.state != .finished)
            #expect(driver.finishCount == 0)
            #expect(driver.submitCount == (scenario == .submissionRejected ? 1 : 0))
            subscription.cancel()
        }
    }

    @Test func wanderFiniteDurationStopsAfterTwelveHoursAndFinishesOnce() async throws {
        let savedDuration = BackgroundRunDuration.shared.seconds
        BackgroundRunDuration.shared.seconds = 43_200
        defer { BackgroundRunDuration.shared.seconds = savedDuration }
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(location(origin))
        let route = RouteExecutionController(planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock,
            wanderBearingSamples: { [0] })
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            clock: clock, driver: driver)
        var acknowledgements = 0
        let subscription = service.movementAcknowledgements.sink { _ in acknowledgements += 1 }
        defer { subscription.cancel() }

        #expect(joystick.setWanderEnabled(true))
        await waitUntil { joystick.phase == .moving && clock.cadenceSleepingCount >= 1 }
        // Wander has no synthetic baseline acknowledgement. Advance once to
        // obtain the first real device ACK, which establishes the duration
        // epoch's timestamp without crediting elapsed time before execution.
        clock.advance(by: .seconds(15))
        await waitUntil { acknowledgements >= 1 && joystick.phase == .moving && clock.cadenceSleepingCount >= 1 }
        await enterBackground(facade)
        for index in 0..<2_880 {
            clock.advance(by: .seconds(15))
            let expected = index + 2
            await waitUntil {
                guard joystick.phase == .moving else { return index == 2_879 }
                return acknowledgements >= expected && clock.cadenceSleepingCount >= 1
            }
            #expect(joystick.phase == .moving || index == 2_879)
        }
        await waitUntil { joystick.phase == .paused || joystick.phase == .neutral }
        #expect(joystick.phase == .paused)
        #expect(facade.state == .finished)
        #expect(driver.submitCount == 1)
        #expect(driver.finishCount == 1)
        let request = try #require(driver.requests.first)
        #expect(request.goal == .finiteDuration(seconds: 43_200))
        let progress = try #require(driver.lastProgress)
        #expect(progress.cumulativeAcknowledgedDurationSeconds == 43_200)

        let writesAtTerminal = await device.moveCount
        for _ in 0..<4 { clock.advance(by: .seconds(15)); await Task.yield() }
        #expect(await device.moveCount == writesAtTerminal)
    }

    @Test func fixedPositionFiniteDurationFiltersRawServiceAcknowledgementDuplicate() async throws {
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(location(origin))
        let positionHold = PositionHoldController(service: service, clock: clock,
            interval: .seconds(10), cadence: .seconds(5))
        let route = RouteExecutionController(planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            positionHold: positionHold, clock: clock, driver: driver)
        var holdAcknowledgements = 0
        var rawAcknowledgements = 0
        let holdSubscription = positionHold.movementAcknowledgements.sink { _ in holdAcknowledgements += 1 }
        let rawSubscription = service.movementAcknowledgements.sink { _ in rawAcknowledgements += 1 }
        defer { holdSubscription.cancel(); rawSubscription.cancel() }

        #expect(service.teleport(to: TeleportCandidate(place: place(origin))))
        await waitUntil { positionHold.phase == .running && holdAcknowledgements == 1 && clock.holdSleepingCount >= 1 }
        await enterBackground(facade)
        clock.advance(by: .seconds(5))
        await waitUntil {
            guard positionHold.phase == .running else { return false }
            return holdAcknowledgements == 2 && clock.holdSleepingCount >= 1
        }
        clock.advance(by: .seconds(5))
        await waitUntil { positionHold.phase == .completed && holdAcknowledgements == 3 }

        #expect(rawAcknowledgements == 3)
        #expect(facade.state == .finished)
        #expect(driver.submitCount == 1)
        #expect(driver.finishCount == 1)
        let request = try #require(driver.requests.first)
        #expect(request.goal == .finiteDuration(seconds: 10))
        let progress = try #require(driver.lastProgress)
        #expect(progress.acknowledgedWrites == Int64(holdAcknowledgements))
        #expect(progress.cumulativeAcknowledgedDurationSeconds == 10)

        let writesAtTerminal = await device.moveCount
        for _ in 0..<4 { clock.advance(by: .seconds(5)); await Task.yield() }
        #expect(await device.moveCount == writesAtTerminal)
    }

    @Test func fixedPositionConnectionRecoveryPreservesPausedNoticeAndRequiresExplicitRetry() async throws {
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(location(origin))
        let positionHold = PositionHoldController(service: service, clock: clock,
            interval: .seconds(60), cadence: .seconds(5))
        let route = RouteExecutionController(planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            positionHold: positionHold, clock: clock, driver: driver)

        #expect(service.teleport(to: TeleportCandidate(place: place(origin))))
        await waitUntil {
            guard positionHold.phase == .running, clock.holdSleepingCount >= 1 else { return false }
            return await device.moveCount == 2
        }
        let pausedIntent = try #require(positionHold.intent)

        service.setMovementConnectionAvailable(false)
        await waitUntil {
            positionHold.phase == .paused && facade.noticeKey == "background.positionPaused"
        }
        #expect(!positionHold.canRetry)

        service.setMovementConnectionAvailable(true)
        await waitUntil {
            positionHold.phase == .paused && facade.noticeKey == "background.positionPaused" &&
                positionHold.canRetry
        }
        let writesBeforeRetry = await device.moveCount
        #expect(positionHold.retry())
        await waitUntil {
            guard positionHold.phase == .running, clock.holdSleepingCount >= 1 else { return false }
            return await device.moveCount >= writesBeforeRetry + 2
        }
        await waitUntil { driver.submitCount == 2 }
        let retriedIntent = try #require(positionHold.intent)
        #expect(retriedIntent.id != pausedIntent.id)
        #expect(retriedIntent.lease != pausedIntent.lease)
        #expect(await device.moveCount == writesBeforeRetry + 2)
    }

    @Test func finiteRouteStillUsesDistanceGoalAndFinishesAtTheActualEndpoint() async throws {
        let clock = DurationIntegrationClock()
        let device = DurationIntegrationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        let destination = GeoCoordinate(latitude: 25.000001, longitude: 121)!
        service.observeRealLocation(location(origin))
        let draft = RouteDraft(values: [
            .place(place(origin)), .place(place(destination))
        ])!
        let route = RouteExecutionController(draft: draft,
            planner: DurationIntegrationPlanner(), commands: service,
            search: DurationIntegrationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let driver = DurationIntegrationDriver()
        let facade = makeFacade(service: service, route: route, joystick: joystick,
            clock: clock, driver: driver)

        #expect(route.start())
        await waitUntil { route.phase == .running && clock.cadenceSleepingCount >= 1 }
        clock.advance(by: .seconds(15))
        await waitUntil { route.phase == .editing && driver.finishCount == 1 }
        #expect(facade.state == .finished)
        let request = try #require(driver.requests.first)
        #expect(request.goal != .finiteDuration(seconds: 43_200))
        if case .finiteDistance = request.goal { } else {
            Issue.record("finite route did not submit a distance goal")
        }
        let progress = try #require(driver.lastProgress)
        #expect(progress.cumulativeAcknowledgedDurationSeconds == 0)
    }

    private func makeFacade(service: ServiceController,
                            route: RouteExecutionController,
                            joystick: JoystickMovementController,
                            positionHold: PositionHoldController? = nil,
                            clock: DurationIntegrationClock,
                            driver: DurationIntegrationDriver) -> MovementContinuationController {
        let recovery = ConnectionRecoveryController(service: service, route: route,
            joystick: joystick, probe: DurationIntegrationProbe(), clock: clock)
        let facade = MovementContinuationController(service: service, route: route,
            joystick: joystick, recovery: recovery, positionHold: positionHold,
            clock: clock, driver: driver) { kind, progress in
                ("Continuing \(kind.rawValue)",
                 "Writes \(progress.acknowledgedWrites)")
            }
        facade.sceneDidBecomeActive()
        return facade
    }

    /// Only background time counts toward the run time.
    private func enterBackground(_ facade: MovementContinuationController) async {
        await waitUntil { facade.hasRuntime }
        facade.releaseForInactiveScene()
    }

    private func routeDraft(origin: GeoCoordinate) -> RouteDraft {
        RouteDraft(values: [
            .place(place(origin)),
            .place(place(GeoCoordinate(latitude: origin.latitude + 0.01, longitude: origin.longitude)!))
        ])!
    }

    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private func location(_ coordinate: GeoCoordinate) -> RealLocationObservation {
        RealLocationObservation(latitude: coordinate.latitude, longitude: coordinate.longitude,
            horizontalAccuracy: 1, observedAt: Date())!
    }

    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

@MainActor
private final class DurationIntegrationDriver: ContinuedProcessingDriving {
    enum Scenario: Equatable, Sendable {
        case normal
        case registrationRejected
        case submissionRejected
    }

    let scenario: Scenario
    private(set) var submitCount = 0
    private(set) var finishCount = 0
    private(set) var requests: [ContinuedProcessingRequest] = []
    private(set) var lastProgress: ContinuedProcessingProgress?

    init(scenario: Scenario = .normal) { self.scenario = scenario }

    func register() -> Bool { scenario != .registrationRejected }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        submitCount += 1
        requests.append(request)
        if scenario == .submissionRejected { throw ContinuedProcessingFailure.submissionRejected }
        onEvent(.launched(ContinuedProcessingGrant(requestID: request.requestID,
            movementID: request.movementID, lease: request.lease)))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress,
                title: String, subtitle: String) {
        lastProgress = progress
    }

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        finishCount += 1
        return success ? .success : .failed
    }

    func cancel(requestID: UUID) {}
}

private actor DurationIntegrationDevice: DeviceService {
    private(set) var moveCount = 0
    private(set) var coordinates: [GeoCoordinate] = []

    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate,
                   dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        moveCount += 1
        coordinates.append(coordinate)
        return .acknowledged
    }
}

private struct DurationIntegrationPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct DurationIntegrationSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}

private struct DurationIntegrationProbe: TunnelProbing {
    func check() async throws {}
}

private final class DurationIntegrationClock: RouteClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Duration
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []

    var now: Duration { lock.withLock { instant } }
    var sleepingCount: Int { lock.withLock { sleepers.count } }
    var cadenceSleepingCount: Int {
        lock.withLock { sleepers.values.filter { $0.duration <= .seconds(1) }.count }
    }
    var holdSleepingCount: Int {
        lock.withLock { sleepers.values.filter { $0.duration >= .seconds(4) }.count }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let wasCancelled = lock.withLock {
                    if cancelled.remove(id) != nil { return true }
                    sleepers[id] = Sleeper(deadline: instant + duration, duration: duration,
                        continuation: continuation)
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
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            instant += duration
            let due = sleepers.filter { $0.value.deadline <= instant }
            for id in due.keys { sleepers.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        for continuation in continuations { continuation.resume() }
    }
}
