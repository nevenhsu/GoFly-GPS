import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ServiceJoystickCommandsTests {
    @Test(arguments: [1, 2, 3])
    func purePreparationRetriesWithoutWritingOrInstalling(successAt: Int) async {
        let device = JoystickControlledDevice(failuresBeforeSuccess: successAt - 1)
        let service = ServiceController(service: device)
        let old = MovementTaskLease()
        #expect(service.movementAuthority.install(old, replacing: service.movementAuthority.snapshot))
        #expect(service.movementAuthority.updateHealth(.confirmedHealthy, for: old))
        let intent = JoystickMovementIntent()
        let result = await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision)
        #expect(result == .prepared)
        #expect(await device.preparations == successAt)
        #expect(await device.coordinates.isEmpty)
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(service.movementAuthority.snapshot.lease == old)
        #expect(service.joystickInputRevision(executionID: intent.id, lease: intent.lease) != nil)
    }
    @Test(arguments: [false, true])
    func preparationCancelSettlesOnlyAfterActualReturnOrExhaustion(duringCall: Bool) async throws {
        let device = JoystickControlledDevice(failuresBeforeSuccess: duringCall ? 0 : 3)
        if duringCall { await device.holdPreparation() }
        let service = ServiceController(service: device)
        let intent = JoystickMovementIntent()
        var returned: JoystickPreparationOutcome?
        let begin = Task { returned = await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        if duringCall { await wait { await device.preparing } }
        else { await wait { service.preparedOperation?.state == .failed(.pairingRequired) } }
        let id = try #require(service.preparedOperation?.id)
        #expect(service.cancelPreparation(id: id))
        if duringCall {
            #expect(returned == nil && service.nativeBusy)
            await device.releasePreparation()
        }
        await wait { returned != nil }
        #expect(returned == .cancelled)
        #expect(service.canBeginJoystick)
        #expect(await device.coordinates.isEmpty)
        #expect(await device.clears == 0)
        if returned != nil { await begin.value }
    }
    @Test func retryExhaustedPureRoundKeepsOriginalIntentAndContinuation() async throws {
        let device = JoystickControlledDevice(failuresBeforeSuccess: 3)
        let service = ServiceController(service: device), intent = JoystickMovementIntent()
        var returned: JoystickPreparationOutcome?
        let begin = Task { returned = await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { service.preparedOperation?.state == .failed(.pairingRequired) }
        let id = try #require(service.preparedOperation?.id)
        #expect(returned == nil)
        await device.allowPreparationSuccess()
        #expect(service.retryPreparedOperation(id: id))
        #expect(service.preparedOperation?.source == .joystick(intent))
        await wait { returned != nil }
        #expect(returned == .prepared)
        #expect(await device.preparations == 4)
        #expect(await device.coordinates.isEmpty)
        await begin.value
    }

    @Test func firstStepClaimsOnlyAtNativeAndReturnsTheActualCoordinate() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = JoystickDisplacement(bearingDegrees: 90, distanceMeters: 10)!
        let expected = JoystickGeodesy.destination(from: origin, displacement: displacement)
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: displacement) }
        await wait { await device.waiting }
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(await device.coordinates == [expected])
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await step.value == .acknowledged(expected))
        #expect(service.confirmedSimulatedLocation == expected)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
    }
    @Test func missingOriginEndsOnlyTheNewGestureWithDomainFailure() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let old = MovementTaskLease()
        #expect(service.movementAuthority.install(old, replacing: service.movementAuthority.snapshot))
        #expect(service.movementAuthority.updateHealth(.confirmedHealthy, for: old))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let revision = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let outcome = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: revision, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!)
        #expect(outcome == .notSent(.originUnavailable))
        #expect(service.movementAuthority.snapshot.lease == old)
        #expect(service.canBeginJoystick)
        #expect(await device.coordinates.isEmpty)
    }
    @Test func fifoHeadUsesThePrecedingOldRoutesActualAcknowledgementAsOrigin() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!, end = GeoCoordinate(latitude: 26, longitude: 122)!
        let place: (GeoCoordinate) -> MapPlace = { MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0) }
        let old = RouteExecutionIntent(draft: RouteDraft(start: .place(place(start)), destination: .place(place(end)))!,
            route: try PlannedRoute(points: [start,end], from: start, to: end))
        let beginning = Task { await service.beginRoute(old, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await beginning.value == .acknowledged)
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let next = GeoCoordinate(latitude: 25.1, longitude: 121.1)!
        let oldTick = Task { await service.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1,
            expectedControlRevision: service.routeControlRevision(executionID: old.id, lease: old.lease)!, coordinate: next) }
        await wait { await device.waiting }
        let revision = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = JoystickDisplacement(bearingDegrees: 180, distanceMeters: 5)!
        let expected = JoystickGeodesy.destination(from: next, displacement: displacement)
        var submitted = false
        let first = Task { submitted = true; return await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: revision, displacement: displacement) }
        await wait { submitted }
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await oldTick.value == .acknowledged)
        await wait { await device.coordinates.count == 3 }
        #expect(await device.coordinates.last == expected)
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await first.value == .acknowledged(expected))
        #expect(service.confirmedSimulatedLocation == expected)
    }

    @Test(arguments: [false, true])
    func normalReleaseWaitsForActualReturnAndPublishesOnlyAClaimedAcknowledgement(claimed: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting }
        let coordinate = try #require(await device.coordinates.last)
        if claimed { #expect(await device.claim()) }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(!service.canBeginJoystick)
        #expect(await service.beginJoystick(JoystickMovementIntent(), expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .cancelled)
        var settlement: JoystickIdleSettlement?
        let idle = Task { settlement = await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) }
        await Task.yield()
        #expect(settlement == nil)
        if !claimed { #expect(!(await device.claim())) }
        await device.finish(claimed ? .acknowledged : .notSent(.operationCancelled))
        #expect(await step.value == (claimed ? .acknowledged(coordinate) : .inputCancelled))
        await wait { settlement != nil }
        #expect(settlement == .settled)
        #expect(service.canBeginJoystick)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(service.confirmedSimulatedLocation == (claimed ? coordinate : nil))
        #expect(await device.clears == 0)
        await idle.value
    }
    @Test(arguments: [false, true])
    func inputRevisionInvalidatesOnlyAvailableWorkAndTheNextStepUsesLatestRecipe(claimed: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let initial = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let original = JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: initial, displacement: original) }
        await wait { await device.waiting }
        let originalCoordinate = try #require(await device.coordinates.last)
        if claimed { #expect(await device.claim()) }
        let revised = try #require(service.reviseJoystickInput(executionID: intent.id, lease: intent.lease))
        #expect(revised.generation == initial.generation && revised.revision == initial.revision + 1)
        if !claimed { #expect(!(await device.claim())) }
        await device.finish(claimed ? .acknowledged : .notSent(.operationCancelled))
        #expect(await step.value == (claimed ? .acknowledged(originalCoordinate) : .inputCancelled))
        let stale = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: claimed ? 2 : 1,
            expectedInputRevision: initial, displacement: original)
        #expect(stale == .inputCancelled)
        let latest = JoystickDisplacement(bearingDegrees: 90, distanceMeters: 2)!
        let origin = try #require(service.currentJoystickOrigin)
        let next = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: claimed ? 2 : 1,
            expectedInputRevision: revised, displacement: latest) }
        await wait { await device.waiting }
        let expected = JoystickGeodesy.destination(from: origin, displacement: latest)
        #expect(await device.coordinates.last == expected)
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await next.value == .acknowledged(expected))
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
    }

    @Test(arguments: [0, 1, 2, 3])
    func releaseCannotEraseUnknownOrMalformedRepliesAndOnlyStopClearsQuarantine(profile: Int) async throws {
        let (service, device, intent) = await preparedService()
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting }
        if profile == 1 || profile == 2 { #expect(await device.claim()) }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        let result: PointDeliveryOutcome = profile == 2 ? .notSent(.serviceUnavailable) : (profile == 3 ? .acknowledged : .unconfirmed(.serviceUnavailable))
        await device.finish(result)
        #expect(await step.value == .unconfirmed(.serviceUnavailable))
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == .requiresStop(.serviceUnavailable))
        #expect(!service.canBeginJoystick && !service.canTeleport && service.phase == .repairRequired)
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(service.stop())
        await wait { !service.nativeBusy }
        #expect(service.phase == .stopped && service.canBeginJoystick && service.canTeleport)
        #expect(await device.clears == 1)
    }
    @Test(arguments: [false, true])
    func watchdogKeepsActualOwnershipAndLateACKCannotUndoAClaimedTimeout(claimed: Bool) async throws {
        let watchdog = ManualServiceWatchdog()
        let (service, device, intent) = await preparedService(watchdog: watchdog)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        if claimed { #expect(await device.claim()) }
        watchdog.fireLatest()
        await wait { service.error == .operationTimedOut }
        #expect(service.nativeBusy)
        #expect(!service.canBeginJoystick)
        await device.finish(claimed ? .acknowledged : .notSent(.operationCancelled))
        #expect(await step.value == (claimed ? .unconfirmed(.operationTimedOut) : .notSent(.device(.operationTimedOut))))
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == (claimed ? .requiresStop(.operationTimedOut) : .settled))
        #expect(!service.nativeBusy)
    }
    @Test(arguments: [false, true])
    func stopBeforeActualReturnWinsAgainstLateUnknownAndCancelsPreparationAwait(claimed: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting }
        if claimed { #expect(await device.claim()) }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(service.stop())
        if !claimed { #expect(!(await device.claim())) }
        #expect(await device.clears == 0)
        await device.finish(.unconfirmed(.serviceUnavailable))
        #expect(await step.value == .cancelled)
        await wait { !service.nativeBusy }
        #expect(service.phase == .stopped && service.canBeginJoystick)
        #expect(await device.clears == 1)
        await device.holdPreparation()
        let next = JoystickMovementIntent()
        var returned: JoystickPreparationOutcome?
        let begin = Task { returned = await service.beginJoystick(next, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { await device.preparing }
        #expect(service.stop())
        await device.releasePreparation()
        await wait { returned != nil && !service.nativeBusy }
        #expect(returned == .cancelled)
        #expect(service.canBeginJoystick && service.phase == .stopped)
        if returned != nil { await begin.value }
    }

    @Test func pauseResumeIsNeutralAndNewGestureClaimsBeforeOldContextCleanup() async throws {
        let (service, device, old) = await preparedService()
        #expect(!service.releaseJoystick(executionID: old.id, lease: old.lease, disposition: .pause))
        let oldInput = try #require(service.joystickInputRevision(executionID: old.id, lease: old.lease))
        let first = Task { await service.sendJoystickStep(executionID: old.id, lease: old.lease, sequence: 1,
            expectedInputRevision: oldInput, displacement: JoystickDisplacement(bearingDegrees: 90, distanceMeters: 1)!) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        guard case .acknowledged(let position) = await first.value else { Issue.record("expected first ACK"); return }
        #expect(service.releaseJoystick(executionID: old.id, lease: old.lease, disposition: .pause))
        #expect(await service.waitForJoystickIdle(executionID: old.id, lease: old.lease) == .settled)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.resumeJoystick(executionID: old.id, lease: old.lease))
        #expect(!service.releaseJoystick(executionID: old.id, lease: old.lease, disposition: .pause))
        #expect(service.joystickInputRevision(executionID: old.id, lease: old.lease) == nil)
        #expect(service.reviseJoystickInput(executionID: old.id, lease: old.lease) == nil)
        #expect(await service.sendJoystickStep(executionID: old.id, lease: old.lease, sequence: 2,
            expectedInputRevision: oldInput, displacement: JoystickDisplacement(bearingDegrees: 90, distanceMeters: 1)!) == .cancelled)
        #expect(service.canBeginJoystick)
        let next = JoystickMovementIntent()
        #expect(await service.beginJoystick(next, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        let nextInput = try #require(service.joystickInputRevision(executionID: next.id, lease: next.lease))
        #expect(nextInput.generation != oldInput.generation)
        let displacement = JoystickDisplacement(bearingDegrees: 180, distanceMeters: 1)!
        let second = Task { await service.sendJoystickStep(executionID: next.id, lease: next.lease, sequence: 1,
            expectedInputRevision: nextInput, displacement: displacement) }
        await wait { await device.waiting }
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await second.value == .acknowledged(JoystickGeodesy.destination(from: position, displacement: displacement)))
        #expect(!service.releaseJoystick(executionID: old.id, lease: old.lease, disposition: .endGesture))
        #expect(service.movementAuthority.snapshot.lease == next.lease)
        #expect(service.releaseJoystick(executionID: next.id, lease: next.lease, disposition: .endGesture))
    }
    @Test(arguments: [false, true])
    func freshCASRejectsHealthOrRunStateChangesAfterOriginWithoutHurtingOldOwner(healthChange: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let old = MovementTaskLease()
        #expect(service.movementAuthority.install(old, replacing: service.movementAuthority.snapshot))
        #expect(service.movementAuthority.updateHealth(.confirmedHealthy, for: old))
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let first = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting }
        if healthChange { #expect(service.movementAuthority.updateHealth(.interrupted(.tunnelUnavailable), for: old)) }
        else { #expect(service.movementAuthority.updateRunState(.paused, for: old)) }
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        #expect(await first.value == .notSent(.device(.operationCancelled)))
        #expect(service.movementAuthority.snapshot.lease == old)
        #expect(service.movementAuthority.snapshot.health == (healthChange ? .interrupted(.tunnelUnavailable) : .confirmedHealthy))
        #expect(service.confirmedSimulatedLocation == nil)
    }
    @Test func oldRouteUnknownBeforeManualHeadNeverCallsTheNewNativePointOrClaimsItWasDispatched() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!, end = GeoCoordinate(latitude: 26, longitude: 122)!
        let place: (GeoCoordinate) -> MapPlace = { MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0) }
        let old = RouteExecutionIntent(draft: RouteDraft(start: .place(place(start)), destination: .place(place(end)))!,
            route: try PlannedRoute(points: [start,end], from: start, to: end))
        let beginning = Task { await service.beginRoute(old, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await beginning.value == .acknowledged)
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let oldTick = Task { await service.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1,
            expectedControlRevision: service.routeControlRevision(executionID: old.id, lease: old.lease)!, coordinate: end) }
        await wait { await device.waiting }; #expect(await device.claim())
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        var submitted = false
        let manual = Task { submitted = true; return await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { submitted }
        await device.finish(.unconfirmed(.tunnelUnavailable))
        #expect(await oldTick.value == .unconfirmed(.tunnelUnavailable))
        #expect(await manual.value == .notSent(.device(.tunnelUnavailable)))
        #expect(await device.coordinates == [start,end])
        #expect(!service.canBeginJoystick && service.phase == .repairRequired)
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == .requiresStop(.tunnelUnavailable))
    }

    @Test(arguments: [false, true])
    func releaseSuppressesOnlyAnAvailableWatchdog(claimed: Bool) async throws {
        let watchdog = ManualServiceWatchdog()
        let (service, device, intent) = await preparedService(watchdog: watchdog)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!) }
        await wait { await device.waiting && watchdog.requests.count == 2 }
        if claimed { #expect(await device.claim()) }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        watchdog.fireLatest()
        if claimed { await wait { service.error == .operationTimedOut } }
        else { await Task.yield(); #expect(service.error == nil) }
        #expect(service.nativeBusy)
        await device.finish(claimed ? .acknowledged : .notSent(.operationCancelled))
        #expect(await step.value == (claimed ? .unconfirmed(.operationTimedOut) : .inputCancelled))
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == (claimed ? .requiresStop(.operationTimedOut) : .settled))
    }
    @Test func normalReleaseDuringPurePreparationWaitsForActualReturnWithoutInstallingOrClearing() async {
        let device = JoystickControlledDevice(); await device.holdPreparation()
        let service = ServiceController(service: device), intent = JoystickMovementIntent()
        let old = MovementTaskLease()
        #expect(service.movementAuthority.install(old, replacing: service.movementAuthority.snapshot))
        #expect(service.movementAuthority.updateHealth(.confirmedHealthy, for: old))
        var returned: JoystickPreparationOutcome?
        let begin = Task { returned = await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { await device.preparing }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(returned == nil && service.nativeBusy && !service.canBeginJoystick)
        await device.releasePreparation()
        await wait { returned != nil }
        #expect(returned == .cancelled)
        #expect(service.movementAuthority.snapshot.lease == old)
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == .settled)
        #expect(await device.coordinates.isEmpty)
        #expect(await device.clears == 0)
        await begin.value
    }

    @Test func oldRouteActuallyTicksBetweenPurePrepareRetriesAndSurvivesNewGestureRelease() async throws {
        let device = JoystickControlledDevice(failuresBeforeSuccess: 1), service = ServiceController(service: device)
        let old = try routeIntent()
        let beginning = Task { await service.beginRoute(old, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await beginning.value == .acknowledged)
        await device.holdPreparation()
        let intent = JoystickMovementIntent()
        let preparation = Task { await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { await device.preparing }
        let target = GeoCoordinate(latitude: 25.1, longitude: 121.1)!
        var submitted = false
        let oldTick = Task { submitted = true; return await service.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1,
            expectedControlRevision: service.routeControlRevision(executionID: old.id, lease: old.lease)!, coordinate: target) }
        await wait { submitted }
        await device.releasePreparation()
        await wait { await device.waiting }
        #expect(service.preparedOperation?.attempt.value == 1)
        #expect(await device.coordinates == [old.route.start,target])
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await oldTick.value == .acknowledged)
        #expect(await preparation.value == .prepared)
        #expect(await device.preparations == 2)
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        #expect(service.confirmedSimulatedLocation == target)
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(service.routeControlRevision(executionID: old.id, lease: old.lease) != nil)
        #expect(service.movementAuthority.snapshot.lease == old.lease)
    }
    @Test func oldUnknownCancelsAQueuedPurePrepareContinuationWithoutFalsePreparedOrNativeWork() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let old = try routeIntent()
        let beginning = Task { await service.beginRoute(old, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await beginning.value == .acknowledged)
        let oldTick = Task { await service.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1,
            expectedControlRevision: service.routeControlRevision(executionID: old.id, lease: old.lease)!, coordinate: old.route.end) }
        await wait { await device.waiting }; #expect(await device.claim())
        let intent = JoystickMovementIntent()
        let preparation = Task { await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { service.preparedOperation?.source == .joystick(intent) }
        await device.finish(.unconfirmed(.tunnelUnavailable))
        #expect(await oldTick.value == .unconfirmed(.tunnelUnavailable))
        #expect(await preparation.value == .cancelled)
        #expect(await device.preparations == 0)
        #expect(service.phase == .repairRequired && !service.canBeginJoystick)
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == .requiresStop(.tunnelUnavailable))
    }
    private func routeIntent() throws -> RouteExecutionIntent {
        let start = GeoCoordinate(latitude: 25, longitude: 121)!, end = GeoCoordinate(latitude: 26, longitude: 122)!
        let place: (GeoCoordinate) -> MapPlace = { MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0) }
        return RouteExecutionIntent(draft: RouteDraft(start: .place(place(start)), destination: .place(place(end)))!,
            route: try PlannedRoute(points: [start,end], from: start, to: end))
    }
    private func preparedService(watchdog: ManualServiceWatchdog? = nil) async -> (ServiceController, JoystickControlledDevice, JoystickMovementIntent) {
        let device = JoystickControlledDevice()
        let service = watchdog.map { ServiceController(service: device, watchdogSleep: $0.sleep) } ?? ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        return (service, device, intent)
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }

}

actor JoystickControlledDevice: DeviceService {
    var preparations = 0
    var coordinates: [GeoCoordinate] = []
    var clears = 0
    var failuresBeforeSuccess: Int
    var pausePreparation = false
    private var preparation: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<PointDeliveryOutcome, Never>?
    private var gate: PointDispatchGate?
    init(failuresBeforeSuccess: Int = 0) { self.failuresBeforeSuccess = failuresBeforeSuccess }
    var waiting: Bool { pending != nil }
    var preparing: Bool { preparation != nil }
    func prepare() async throws {
        preparations += 1
        if pausePreparation { await withCheckedContinuation { preparation = $0 } }
        if preparations <= failuresBeforeSuccess { throw DeviceServiceFailure.pairingRequired }
    }
    func holdPreparation() { pausePreparation = true }
    func releasePreparation() { pausePreparation = false; preparation?.resume(); preparation = nil }
    func allowPreparationSuccess() { failuresBeforeSuccess = 0 }
    func clearLocation() async throws { clears += 1 }
    func resetClientConnection() async throws {}
    var rebuilds = 0
    func rebuildClientConnection() async throws { rebuilds += 1 }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        coordinates.append(coordinate); gate = dispatch
        return await withCheckedContinuation { pending = $0 }
    }
    func claim() -> Bool { gate?.claim() ?? false }
    func finish(_ outcome: PointDeliveryOutcome) { pending?.resume(returning: outcome); pending = nil }
}
