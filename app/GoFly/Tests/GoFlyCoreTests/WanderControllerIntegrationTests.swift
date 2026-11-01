import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct WanderControllerIntegrationTests {
    @Test func planningCanStartWithoutAnOriginButMovementCannot() {
        let controller = JoystickMovementController(commands: ServiceController(service: JoystickControlledDevice()))
        #expect(controller.requiresOrigin)
        #expect(controller.canStartWanderPlanning)
        #expect(!controller.canSetWanderEnabled)
        #expect(!controller.canBeginGesture)
    }

    @Test func manualTakeoverRequiresAReplacementRoadBeforeAutomaticMovementResumes() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let firstDestination = GeoCoordinate(latitude: 25.001, longitude: 121)!
        let firstPlace = place(firstDestination)
        let firstRoute = try PlannedRoute(points: [origin, firstDestination])
        let controller = JoystickMovementController(commands: service, clock: clock)
        #expect(controller.installWanderRoute(target: WanderTarget(place: firstPlace), route: firstRoute))
        #expect(controller.setWanderEnabled(true))
        let owner = try #require(controller.intent)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }

        let gesture = UUID(), input = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: gesture, input: input))
        clock.advance(by: .seconds(1)); await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: gesture))
        #expect(controller.wanderNeedsReplan)
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(10))
        #expect(!(await device.waiting))

        #expect(await controller.pauseForWanderReplan())
        #expect(controller.phase == .paused)
        let newOrigin = try #require(service.currentJoystickOrigin)
        let nextDestination = firstDestination
        let nextPlace = firstPlace
        let nextRoute = try PlannedRoute(points: [newOrigin, nextDestination])
        #expect(controller.replaceWanderRouteAndResume(target: WanderTarget(place: nextPlace), route: nextRoute))
        #expect(controller.intent == owner)
        #expect(controller.wanderTarget?.place == nextPlace)
        #expect(controller.wanderRoute == nextRoute)
        #expect(controller.wanderProgressMeters == 0 && !controller.wanderNeedsReplan)
        #expect(controller.phase == .moving)
        #expect(controller.setWanderEnabled(false))
        await wait { controller.phase == .neutral }
    }

    /// A wander finger passing the joystick centre keeps the override: the
    /// arrow keeps its bearing, holds still, and the road does not take over.
    @Test func aWanderFingerAtTheCentreHoldsStillAndKeepsItsBearing() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let destination = GeoCoordinate(latitude: 25.001, longitude: 121)!
        let controller = JoystickMovementController(commands: service, clock: clock)
        #expect(controller.installWanderRoute(target: WanderTarget(place: place(destination)),
                                              route: try PlannedRoute(points: [origin, destination])))
        #expect(controller.setWanderEnabled(true))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.markerGlideRoute == controller.wanderRoute)

        let gesture = UUID()
        #expect(controller.beginGesture(id: gesture, input: JoystickInput(bearingDegrees: 90, strength: 1)!))
        #expect(controller.updateGesture(id: gesture, input: JoystickInput(bearingDegrees: 0, strength: 0)!))
        #expect(controller.activeGestureID == gesture && !controller.wanderNeedsReplan)
        #expect(controller.displayBearingDegrees == 90)
        #expect(controller.markerGlideRoute == nil, "The arrow glides straight while a finger steers")
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(!(await device.waiting), "No road step while the finger rests at the centre")

        #expect(controller.updateGesture(id: gesture, input: JoystickInput(bearingDegrees: 180, strength: 1)!))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: gesture))
        #expect(controller.wanderNeedsReplan, "Only lifting the finger hands the wander back to the road")
        #expect(controller.setWanderEnabled(false))
    }

    @Test func rejoiningWalksStraightToTheNearestRoutePointNotYetPassed() throws {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!, b = GeoCoordinate(latitude: 25.001, longitude: 121)!
        let c = GeoCoordinate(latitude: 25.002, longitude: 121)!, d = GeoCoordinate(latitude: 25.003, longitude: 121)!
        let route = try PlannedRoute(points: [a, b, c, d])
        let offRoad = GeoCoordinate(latitude: 25.0011, longitude: 121.0005)!
        let rejoin = try #require(WanderPlanningCoordinator.rejoinRoute(from: offRoad, onto: route, passedMeters: 0))
        #expect(rejoin.points == [offRoad, b, c, d])
        let past = try #require(WanderPlanningCoordinator.rejoinRoute(
            from: offRoad, onto: route, passedMeters: route.cumulativeDistancesMeters[2]))
        #expect(past.points == [offRoad, c, d], "A point already passed is never walked back to")
    }

    @Test func realArrivalWithoutNextTargetPausesAuthorityAndGoThenRetryUsesTheSameLease() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), samples = IntegrationWanderSamples([[0], []])
        let service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent)
        let firstPoint = GeoCoordinate(latitude: 25.00001, longitude: 121)!
        #expect(controller.applyWanderTarget(place(firstPoint)))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.coordinates == [firstPoint])
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.phase == .suspended }
        #expect(controller.suspensionReason == .targetUnavailable && controller.wanderNeedsTarget)
        #expect(service.movementAuthority.snapshot.lease == operation.lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(service.confirmedSimulatedLocation == firstPoint)
        let nextPoint = GeoCoordinate(latitude: 25.00002, longitude: 121)!
        let nextPlace = place(nextPoint)
        let nextRoute = try PlannedRoute(points: [firstPoint, nextPoint])
        #expect(controller.installNextWanderRouteAndResume(target: WanderTarget(place: nextPlace), route: nextRoute))
        #expect(controller.intent == operation && service.movementAuthority.snapshot.runState == .running)
        #expect(controller.wanderRoute == nextRoute && !controller.wanderNeedsTarget)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.coordinates.last == nextPoint)
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.phase == .suspended }
        #expect(controller.lastAcknowledgedCoordinate == nextPoint)
        #expect(controller.setWanderEnabled(false)); await wait { controller.phase == .neutral }
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(await device.preparations == 1)
        #expect(await device.clears == 0)
    }

    @Test func failedRouteResumeKeepsThePriorDestinationAndRoute() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let origin = try #require(service.currentJoystickOrigin)
        let oldDestination = GeoCoordinate(latitude: 25.001, longitude: 121)!
        let oldPlace = place(oldDestination), oldRoute = try PlannedRoute(points: [origin, oldDestination])
        let controller = JoystickMovementController(commands: service, clock: clock)
        #expect(controller.installWanderRoute(target: WanderTarget(place: oldPlace), route: oldRoute))
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.pause())
        await wait { controller.phase == .paused }

        controller.recoveryProbeDidStart()
        let replacement = GeoCoordinate(latitude: 25.002, longitude: 121)!
        let replacementPlace = place(replacement)
        let replacementRoute = try PlannedRoute(points: [try #require(service.currentJoystickOrigin), replacement])
        #expect(!controller.replaceWanderRouteAndResume(target: WanderTarget(place: replacementPlace), route: replacementRoute))
        #expect(controller.phase == .paused)
        #expect(controller.wanderTarget?.place == oldPlace)
        #expect(controller.wanderRoute == oldRoute)
        #expect(controller.intent == operation)
        controller.recoveryProbeDidFinish()
        controller.releaseForInactiveScene()
        #expect(!controller.replaceWanderRouteAndResume(target: WanderTarget(place: replacementPlace), route: replacementRoute))
        #expect(controller.phase == .paused && controller.wanderTarget?.place == oldPlace && controller.wanderRoute == oldRoute)
        controller.sceneDidBecomeActive()
        #expect(controller.setWanderEnabled(false))
        await wait { controller.phase == .neutral }
    }

    @Test(arguments: ["stop", "claimUnknown", "availableCancel", "failedPrepare"])
    func retiredLocalWanderIsInvalidatedOnlyByAcceptedStopOrAnotherActualClaim(boundary: String) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        await wait { clock.sleepingCount == 1 }
        controller.releaseForInactiveScene()
        await wait { controller.phase == .suspended && !service.nativeBusy }
        controller.sceneDidBecomeActive()
        #expect(controller.wanderEnabled && controller.intent == nil)
        if boundary == "stop" {
            #expect(service.stop())
            await wait { !service.nativeBusy }
        } else {
            #expect(service.teleport(to: TeleportCandidate(place: place(GeoCoordinate(latitude: 26, longitude: 122)!))))
            if boundary == "failedPrepare" {
                // Point repair is owned by the adapter; the facade does not
                // multiply a failed Go into three preparation rounds.
                await wait { await device.waiting }
                await device.finish(.notSent(.pairingRequired))
                await wait { service.preparedOperation?.state == .failed(.pairingRequired) }
                #expect(controller.wanderEnabled && controller.phase == .suspended)
                #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
            } else {
                await wait { await device.waiting }
                #expect(controller.wanderEnabled && controller.phase == .suspended)
                if boundary == "claimUnknown" {
                    #expect(await device.claim())
                    await wait { !controller.wanderEnabled }
                    await device.finish(.unconfirmed(.serviceUnavailable))
                } else {
                    #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
                    #expect(!(await device.claim()))
                    await device.finish(.notSent(.operationCancelled))
                }
                await wait { !service.nativeBusy }
            }
        }
        if boundary == "stop" || boundary == "claimUnknown" {
            #expect(!controller.wanderEnabled && controller.phase == .neutral && controller.wanderTarget == nil)
            #expect(!controller.resume() && !controller.retryWander())
        } else {
            #expect(controller.wanderEnabled && controller.phase == .suspended && controller.canResume)
            #expect(controller.setWanderEnabled(false))
        }
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == (boundary == "stop" ? 0 : 1))
        if boundary == "claimUnknown" { #expect(service.stop()); await wait { !service.nativeBusy } }
    }

    @Test(arguments: [false, true])
    func unclaimedAutoFailureBeforeOrAfterInstallationAllowsExplicitRetryWithANewIntent(installed: Bool) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let old = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        if installed {
            #expect(await device.claim()); await device.finish(.acknowledged)
            await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
            await wait { await device.waiting }
        }
        let confirmed = service.confirmedSimulatedLocation
        await device.finish(.notSent(.pairingRequired))
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(controller.wanderEnabled && controller.wanderTarget == target)
        // An installed wander retries from the ACK the device still holds.
        #expect(controller.canRetryWander)
        #expect(controller.error == .device(.pairingRequired) && !controller.requiresStop)
        #expect(service.confirmedSimulatedLocation == confirmed)
        #expect(controller.retryWander())
        #expect(controller.intent?.id != old.id && controller.intent?.lease != old.lease)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(controller.setWanderEnabled(false))
        #expect(!(await device.claim())); await device.finish(.notSent(.operationCancelled))
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(await device.preparations == 2)
        #expect(await device.clears == 0)
    }

    @Test func aClaimedUnknownAutoStepRequiresStopEvenAfterDisablingTheCheckbox() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .seconds(1))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.unconfirmed(.serviceUnavailable))
        await wait { controller.requiresStop && !service.nativeBusy }
        #expect(!controller.retryWander() && !controller.resume())
        controller.clearError()
        #expect(controller.requiresStop && controller.error == .device(.serviceUnavailable))
        #expect(controller.setWanderEnabled(false))
        #expect(controller.requiresStop && controller.phase == .unknown)
        #expect(service.stop()); await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(!controller.wanderEnabled && controller.error == nil)
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == 1)
        #expect(await device.clears == 1)
    }

    private func location() -> RealLocationObservation { RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date())! }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
private final class IntegrationWanderSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Double]]
    init(_ values: [[Double]]) { self.values = values }
    func next() -> [Double] { lock.withLock { values.isEmpty ? [] : values.removeFirst() } }
}
