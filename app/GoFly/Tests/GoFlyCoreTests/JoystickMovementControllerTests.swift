import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct JoystickMovementControllerTests {
    @Test func preparationReservesOneGestureAndStartsFreshCadenceOnlyAfterActualPreparation() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        #expect(controller.phase == .preparing && controller.activeGestureID == finger)
        #expect(!controller.beginGesture(id: UUID(), input: input))
        await wait { commands.preparationWaiting }
        clock.advance(by: .seconds(5))
        #expect(commands.steps.isEmpty)
        commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.phase == .moving && !controller.canPause)
        #expect(controller.lastAcknowledgedCoordinate == nil)
        clock.advance(by: .milliseconds(499))
        #expect(commands.steps.isEmpty)
        clock.advance(by: .milliseconds(1))
        await wait { commands.stepWaiting }
        #expect(commands.steps.count == 1)
        #expect(commands.steps[0].displacement.bearingDegrees == 90)
        #expect(controller.lastAcknowledgedCoordinate == nil)
        clock.advance(by: .seconds(10))
        #expect(commands.steps.count == 1)
        let actual = GeoCoordinate(latitude: 25, longitude: 121)!
        commands.finishStep(.acknowledged(actual))
        await wait { clock.sleepingCount == 1 && controller.canPause }
        #expect(controller.lastAcknowledgedCoordinate == actual)
        #expect(controller.lastAcknowledgedBearingDegrees == 90)
        #expect(commands.steps.count == 1)
        clock.advance(by: .milliseconds(499))
        #expect(commands.steps.count == 1)
        #expect(controller.endGesture(id: finger))
        await wait { controller.phase == .neutral }
    }
    @Test func inputAndSpeedChangesRevisePendingWorkButClaimedACKKeepsItsCapturedBearing() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), east = JoystickInput(bearingDegrees: 90, strength: 1)!, west = JoystickInput(bearingDegrees: 270, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: east))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(!controller.updateGesture(id: UUID(), input: west))
        #expect(commands.revisions == 0)
        #expect(controller.updateGesture(id: finger, input: west))
        #expect(commands.revisions == 1)
        #expect(controller.updateGesture(id: finger, input: west))
        #expect(commands.revisions == 1)
        #expect(controller.setSpeed(RouteSpeed(kilometersPerHour: 120)!))
        #expect(commands.revisions == 2)
        let actual = GeoCoordinate(latitude: 24, longitude: 120)!
        commands.finishStep(.acknowledged(actual))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.lastAcknowledgedCoordinate == actual)
        #expect(controller.lastAcknowledgedBearingDegrees == 90)
        #expect(controller.displayBearingDegrees == 270)
        clock.advance(by: .milliseconds(500)); await wait { commands.stepWaiting }
        #expect(commands.steps.last?.revision == commands.inputRevision)
        #expect(commands.steps.last?.displacement.bearingDegrees == 270)
        #expect(abs((commands.steps.last?.displacement.distanceMeters ?? 0) - 120.0 / 3.6 * 0.5) < 1e-9,
                "the manual step is speed × half a second with no cap")
        #expect(controller.endGesture(id: finger))
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 23, longitude: 119)!))
        await wait { controller.phase == .neutral }
        #expect(controller.lastAcknowledgedBearingDegrees == 270)
        #expect(controller.displayBearingDegrees == 270)
    }

    @Test func pauseWaitsForClaimedTruthThenResumeIsNeutralAndNextGestureHasNewIdentity() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), east = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: east))
        #expect(!controller.pause())
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }; commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 121)!))
        await wait { controller.canPause && clock.sleepingCount == 1 }
        let first = try #require(controller.intent)
        clock.advance(by: .milliseconds(500)); await wait { commands.stepWaiting }
        #expect(controller.pause())
        #expect(controller.phase == .pausing && controller.input == nil && controller.activeGestureID == nil)
        #expect(!controller.resume())
        #expect(!controller.beginGesture(id: UUID(), input: east))
        let final = GeoCoordinate(latitude: 25, longitude: 121.001)!
        commands.finishStep(.acknowledged(final))
        await wait { controller.phase == .paused }
        #expect(controller.lastAcknowledgedCoordinate == final)
        #expect(commands.releases == [.pause])
        #expect(controller.resume())
        #expect(controller.phase == .neutral && controller.input == nil)
        clock.advance(by: .seconds(5))
        #expect(commands.steps.count == 2 && clock.sleepingCount == 0)
        #expect(controller.beginGesture(id: UUID(), input: east))
        let next = try #require(controller.intent)
        #expect(next.id != first.id && next.lease != first.lease)
        await wait { commands.preparationWaiting }
        controller.releaseForInactiveScene()
        commands.finishPreparation(.prepared)
        await wait { controller.phase == .neutral }
        #expect(commands.steps.count == 2)
        controller.clearError()
    }

    @Test func inactiveDuringPauseSettlementRetiresTheGestureInsteadOfLeavingAPausedOwner() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        #expect(controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }; commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 121)!))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(controller.pause())
        controller.releaseForInactiveScene()
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25.001, longitude: 121)!))
        await wait { controller.phase == .neutral }
        #expect(!controller.canResume && controller.intent == nil)
        #expect(commands.releases == [.pause, .endGesture])
        clock.advance(by: .seconds(10))
        #expect(commands.steps.count == 2)
    }

    @Test(arguments: [false, true])
    func releaseRejectsRapidRepressUntilActualPreparationOrStepReturns(atStep: Bool) async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 45, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        await wait { commands.preparationWaiting }
        if atStep {
            commands.finishPreparation(.prepared)
            await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
            await wait { commands.stepWaiting }
        }
        #expect(!controller.endGesture(id: UUID()))
        #expect(controller.endGesture(id: finger))
        #expect(controller.phase == .settling && controller.activeGestureID == nil && controller.input == nil)
        #expect(!controller.beginGesture(id: UUID(), input: input))
        #expect(!controller.updateGesture(id: finger, input: input))
        clock.advance(by: .seconds(30))
        #expect(controller.phase == .settling)
        let actual = GeoCoordinate(latitude: 26, longitude: 122)!
        if atStep { commands.finishStep(.acknowledged(actual)) }
        else { commands.finishPreparation(.prepared) }
        await wait { controller.phase == .neutral }
        #expect(controller.lastAcknowledgedCoordinate == (atStep ? actual : nil))
        #expect(controller.lastAcknowledgedBearingDegrees == (atStep ? 45 : nil))
        #expect(commands.steps.count == (atStep ? 1 : 0))
    }

    @Test func immediateReleaseBeforeAsyncEntryNeverStartsPreparationAndZeroInputEndsAnAdmittedGesture() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), full = JoystickInput(bearingDegrees: 0, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: full))
        #expect(controller.endGesture(id: finger))
        await wait { controller.phase == .neutral }
        #expect(commands.intent == nil && !commands.preparationWaiting)
        #expect(!controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 0)!))
        #expect(controller.beginGesture(id: finger, input: full))
        await wait { commands.preparationWaiting }
        #expect(controller.updateGesture(id: finger, input: JoystickInput(bearingDegrees: 90, strength: 0)!))
        #expect(controller.phase == .settling)
        commands.finishPreparation(.cancelled)
        await wait { controller.phase == .neutral }
        #expect(commands.steps.isEmpty)
    }

    @Test func availableCancellationPublishesNoACKAndUsesTheLatestRecipeAfterAFreshCadence() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID()
        #expect(controller.beginGesture(id: finger, input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(controller.updateGesture(id: finger, input: JoystickInput(bearingDegrees: 180, strength: 0.5)!))
        commands.finishStep(.inputCancelled)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.lastAcknowledgedCoordinate == nil && controller.lastAcknowledgedBearingDegrees == nil)
        #expect(!controller.canPause)
        clock.advance(by: .milliseconds(499)); #expect(commands.steps.count == 1)
        clock.advance(by: .milliseconds(1)); await wait { commands.stepWaiting }
        #expect(commands.steps.count == 2 && commands.steps.last?.sequence == 1)
        #expect(commands.steps.last?.displacement.bearingDegrees == 180)
        #expect(abs((commands.steps.last?.displacement.distanceMeters ?? 0) - (20.0 / 3.6 * 0.5 * 0.5)) < 1e-14)
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 121)!))
        await wait { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500)); await wait { commands.stepWaiting }
        #expect(commands.steps.last?.sequence == 2)
        #expect(controller.endGesture(id: finger)); commands.finishStep(.inputCancelled)
        await wait { controller.phase == .neutral }
    }

    @Test func releaseWithUnknownCompletionRequiresStopAndCannotBeClearedByUIActions() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 0, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        let operation = try #require(controller.intent)
        #expect(controller.endGesture(id: finger))
        commands.settlement = .requiresStop(.serviceUnavailable)
        commands.finishStep(.unconfirmed(.serviceUnavailable))
        await wait { controller.requiresStop }
        #expect(controller.error == .device(.serviceUnavailable))
        controller.clearError(); controller.releaseForInactiveScene()
        #expect(controller.requiresStop && controller.error == .device(.serviceUnavailable))
        #expect(!controller.beginGesture(id: UUID(), input: input) && !controller.resume())
        #expect(!controller.setSpeed(RouteSpeed(kilometersPerHour: 100)!))
        commands.events.send(.ended(operation.id))
        #expect(controller.phase == .neutral && !controller.requiresStop)
        #expect(controller.lastAcknowledgedCoordinate == nil)
    }

    @Test func timeoutBeforeActualACKRemainsUnknownAndExternalStopOrHandoffSuppressesLateCallbacks() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        #expect(controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        let operation = try #require(controller.intent)
        commands.events.send(.unknown(operation.id, .serviceUnavailable))
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 0, longitude: 0)!))
        commands.events.send(.availabilityChanged)
        #expect(controller.requiresStop && controller.lastAcknowledgedCoordinate == nil)
        commands.events.send(.ended(operation.id))
        #expect(controller.phase == .neutral)
        #expect(controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 180, strength: 1)!))
        await wait { commands.preparationWaiting }
        let next = try #require(controller.intent)
        commands.events.send(.ended(next.id))
        commands.finishPreparation(.prepared)
        #expect(controller.phase == .neutral && controller.activeGestureID == nil)
    }

    @Test func unavailableOriginAndAvailabilityChangesUseOnlyTheCommandBoundaryNotLastACKCache() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 0, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }; commands.finishStep(.acknowledged(GeoCoordinate(latitude: 0, longitude: 0)!))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: finger)); await wait { controller.phase == .neutral }
        commands.currentJoystickOrigin = nil
        var notifications = 0
        let subscription = controller.objectWillChange.sink { notifications += 1 }
        commands.events.send(.availabilityChanged)
        #expect(notifications > 0 && controller.requiresOrigin && !controller.canBeginGesture)
        #expect(controller.lastAcknowledgedCoordinate != nil)
        #expect(!controller.beginGesture(id: UUID(), input: input))
        commands.currentJoystickOrigin = GeoCoordinate(latitude: 1, longitude: 1)!
        commands.events.send(.availabilityChanged)
        #expect(controller.canBeginGesture)
        withExtendedLifetime(subscription) {}
    }

    private func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }
}

@MainActor final class ControlledJoystickCommands: JoystickCommanding {
    struct RecipeStep { let sequence: UInt64; let revision: JoystickInputRevision; let recipe: JoystickStepRecipe }
    struct Step { let sequence: UInt64; let revision: JoystickInputRevision; let displacement: JoystickDisplacement }
    var canBeginJoystick = true
    var currentJoystickOrigin: GeoCoordinate? = GeoCoordinate(latitude: 25, longitude: 121)!
    var movementAdmissionRevision: UInt64 = 0
    let events = PassthroughSubject<JoystickCommandEvent, Never>()
    var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { events.eraseToAnyPublisher() }
    private var preparation: CheckedContinuation<JoystickPreparationOutcome, Never>?
    private var step: CheckedContinuation<JoystickStepOutcome, Never>?
    private var recipeStep: CheckedContinuation<JoystickRecipeStepOutcome, Never>?
    var recipeSteps: [RecipeStep] = []
    var recipeStepWaiting: Bool { recipeStep != nil }
    var streamResumes = 0
    var resumeAllowed = true
    private var idle: [CheckedContinuation<JoystickIdleSettlement, Never>] = []
    var preparationWaiting: Bool { preparation != nil }
    var stepWaiting: Bool { step != nil }
    var intent: JoystickMovementIntent?
    var inputRevision = JoystickInputRevision()
    var steps: [Step] = []
    var revisions = 0
    var releases: [JoystickReleaseDisposition] = []
    var resumes = 0
    var settlement: JoystickIdleSettlement = .settled
    func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome {
        self.intent = intent
        return await withCheckedContinuation { preparation = $0 }
    }
    func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { intent?.id == executionID && intent?.lease == lease ? inputRevision : nil }
    func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? {
        guard joystickInputRevision(executionID: executionID, lease: lease) != nil else { return nil }
        revisions += 1
        inputRevision = JoystickInputRevision(generation: inputRevision.generation, revision: inputRevision.revision + 1)
        return inputRevision
    }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome {
        steps.append(Step(sequence: sequence, revision: expectedInputRevision, displacement: displacement))
        return await withCheckedContinuation { step = $0 }
    }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                          expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome {
        if case .manual(let displacement) = recipe {
            let result = await sendJoystickStep(executionID: executionID, lease: lease, sequence: sequence,
                expectedInputRevision: expectedInputRevision, displacement: displacement)
            switch result {
            case .acknowledged(let coordinate): return .acknowledged(JoystickStepReceipt(actualCoordinate: coordinate,
                actualBearingDegrees: displacement.bearingDegrees, targetID: nil, arrived: false))
            case .notSent(let failure): return .notSent(failure)
            case .unconfirmed(let failure): return .unconfirmed(failure)
            case .inputCancelled: return .inputCancelled
            case .cancelled: return .cancelled
            }
        }
        recipeSteps.append(RecipeStep(sequence: sequence, revision: expectedInputRevision, recipe: recipe))
        return await withCheckedContinuation { recipeStep = $0 }
    }
    func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard resumeAllowed, intent?.id == executionID, intent?.lease == lease else { return false }
        streamResumes += 1; inputRevision = JoystickInputRevision()
        return true
    }
    func finishRecipeStep(_ outcome: JoystickRecipeStepOutcome) {
        if case .acknowledged(let receipt) = outcome { currentJoystickOrigin = receipt.actualCoordinate }
        let pending = recipeStep; recipeStep = nil; pending?.resume(returning: outcome); finishIdle()
    }
    func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool { releases.append(disposition); return true }
    func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool { resumes += 1; inputRevision = JoystickInputRevision(); return true }
    func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement {
        if preparation == nil && step == nil && recipeStep == nil { return settlement }
        return await withCheckedContinuation { idle.append($0) }
    }
    func finishPreparation(_ outcome: JoystickPreparationOutcome) { let pending = preparation; preparation = nil; pending?.resume(returning: outcome); finishIdle() }
    func finishStep(_ outcome: JoystickStepOutcome) { if case .acknowledged(let coordinate) = outcome { currentJoystickOrigin = coordinate }; let pending = step; step = nil; pending?.resume(returning: outcome); finishIdle() }
    private func finishIdle() { if preparation == nil && step == nil && recipeStep == nil { let waiting = idle; idle = []; for value in waiting { value.resume(returning: settlement) } } }
}
