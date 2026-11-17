import Foundation
import Testing
@testable import GoFlyCore

@MainActor
struct PositionHoldProgressTests {
    @Test func finiteDurationAndProgressRejectInvalidValues() {
        let lease = MovementTaskLease()
        let movementID = UUID()
        let makeRequest: (Double) -> ContinuedProcessingRequest? = { seconds in
            ContinuedProcessingRequest(movementID: movementID, lease: lease,
                kind: .fixedPosition, goal: .finiteDuration(seconds: seconds),
                title: "Position hold", subtitle: "Continuing")
        }

        #expect(makeRequest(-1) == nil)
        #expect(makeRequest(0) == nil)
        #expect(makeRequest(.infinity) == nil)
        #expect(makeRequest(.nan) == nil)
        #expect(makeRequest(43_200) != nil)
        #expect(makeRequest(BackgroundRunDuration.maximumSeconds) != nil)
        #expect(makeRequest(BackgroundRunDuration.maximumSeconds + 0.1) == nil)

        #expect(ContinuedProcessingProgress(acknowledgedWrites: 0,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: -1) == nil)
        #expect(ContinuedProcessingProgress(acknowledgedWrites: 0,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: .infinity) == nil)
        #expect(ContinuedProcessingProgress(acknowledgedWrites: 0,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: .nan) == nil)
    }

    @Test func finiteDurationIsAcceptedForAllDurationKinds() {
        for kind in [ContinuedProcessingKind.fixedPosition, .roundTrip, .wander] {
            #expect(makeRequest(kind: kind, seconds: 43_200) != nil)
            #expect(makeRequest(kind: kind, seconds: BackgroundRunDuration.maximumSeconds) != nil)
            #expect(makeRequest(kind: kind, seconds: BackgroundRunDuration.maximumSeconds + 0.1) == nil)
        }
        #expect(makeRequest(kind: .finiteRoute, seconds: 43_200) == nil)
    }

    @Test func finiteDurationUsesPercentageUnitsAtTwelveHours() {
        let request = makeRequest(seconds: 43_200)!
        let exact = ContinuedProcessingProgress(acknowledgedWrites: 1,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: 43_200)!
        let beyondGoal = ContinuedProcessingProgress(acknowledgedWrites: 2,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: 86_400)!

        let exactUnits = ContinuedProcessingProgressUnits.forRequest(request, progress: exact)
        #expect(exactUnits.completedUnitCount == 1_000_000)
        #expect(exactUnits.totalUnitCount == 1_000_001)

        let beyondUnits = ContinuedProcessingProgressUnits.forRequest(request, progress: beyondGoal)
        #expect(beyondUnits.completedUnitCount == 1_000_001)
        #expect(beyondUnits.totalUnitCount == 1_000_002)
    }

    /// iOS expires a continued-processing task whose progress stalls; the
    /// countdown is paused in the foreground, so each write must still move it.
    @Test func finiteDurationUnitsAdvanceWithWritesWhileCountdownIsPaused() {
        let request = makeRequest(kind: .wander, seconds: 3_600)!
        var previous: ContinuedProcessingProgressUnits?
        for writes in Int64(1)...5 {
            let progress = ContinuedProcessingProgress(acknowledgedWrites: writes,
                cumulativeAcknowledgedDistanceMeters: Double(writes) * 7,
                cumulativeAcknowledgedDurationSeconds: 0)!
            let units = ContinuedProcessingProgressUnits.forRequest(request, progress: progress)
            if let previous {
                #expect(units.completedUnitCount > previous.completedUnitCount)
            }
            #expect(units.completedUnitCount < units.totalUnitCount)
            previous = units
        }
    }

    @Test func controllerCompletesFiniteDurationExactlyOnceAndRejectsBadProgress() async {
        let driver = PositionHoldTestDriver()
        let controller = ContinuedProcessingController(driver: driver)
        let request = makeRequest(seconds: 43_200)!

        #expect(controller.register())
        #expect(await controller.begin(request, isForeground: true))
        driver.launch(request)

        let exact = ContinuedProcessingProgress(acknowledgedWrites: 1,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: 43_200)!
        let regressed = ContinuedProcessingProgress(acknowledgedWrites: 2,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: 43_199)!
        let exceeded = ContinuedProcessingProgress(acknowledgedWrites: 2,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: 43_201)!

        #expect(controller.update(requestID: request.requestID, progress: exact,
            title: request.title, subtitle: request.subtitle))
        #expect(!controller.update(requestID: request.requestID, progress: regressed,
            title: request.title, subtitle: request.subtitle))
        #expect(!controller.update(requestID: request.requestID, progress: exceeded,
            title: request.title, subtitle: request.subtitle))
        #expect(controller.update(requestID: request.requestID, progress: exact,
            title: request.title, subtitle: request.subtitle))
        #expect(controller.state == .running)
        #expect(controller.hasRuntime)
        #expect(driver.submitCount == 1)
        #expect(driver.finishCalls == 0)
        #expect(!controller.finishFiniteArrival(requestID: request.requestID))
        #expect(controller.finishFiniteTask(requestID: request.requestID))
        #expect(controller.state == .finished)
        #expect(controller.completionOutcome == .success)
        #expect(driver.finishCalls == 1)
        #expect(!controller.finishFiniteTask(requestID: request.requestID))
        #expect(driver.finishCalls == 1)
    }

    @Test func finiteDistanceAndIndeterminateUnitsRemainUnchanged() {
        let finite = ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
            kind: .finiteRoute, goal: .finiteDistance(meters: 40),
            title: "Route", subtitle: "Continuing")!
        let finiteProgress = ContinuedProcessingProgress(acknowledgedWrites: 4,
            cumulativeAcknowledgedDistanceMeters: 40)!
        let finiteUnits = ContinuedProcessingProgressUnits.forRequest(finite, progress: finiteProgress)
        #expect(finiteUnits.totalUnitCount == 1_000_000)
        #expect(finiteUnits.completedUnitCount == 999_999)

        let indeterminate = ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
            kind: .roundTrip, goal: .experimentalIndeterminate,
            title: "Round trip", subtitle: "Continuing")!
        let indeterminateProgress = ContinuedProcessingProgress(acknowledgedWrites: 7,
            cumulativeAcknowledgedDistanceMeters: 0)!
        let indeterminateUnits = ContinuedProcessingProgressUnits.forRequest(indeterminate,
            progress: indeterminateProgress)
        #expect(indeterminateUnits.totalUnitCount == -1)
        #expect(indeterminateUnits.completedUnitCount == 7)
    }

    @Test func finiteDurationRatiosSaturateWithoutOverflow() {
        let request = makeRequest(seconds: 43_200)!
        let progress = ContinuedProcessingProgress(acknowledgedWrites: Int64.max,
            cumulativeAcknowledgedDistanceMeters: 0,
            cumulativeAcknowledgedDurationSeconds: .greatestFiniteMagnitude)!
        let units = ContinuedProcessingProgressUnits.forRequest(request, progress: progress)

        #expect(units.totalUnitCount == 1_001_000_000)
        #expect(units.completedUnitCount == 1_000_999_999)
    }

    private func makeRequest(kind: ContinuedProcessingKind = .fixedPosition,
                             seconds: Double) -> ContinuedProcessingRequest? {
        ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
            kind: kind, goal: .finiteDuration(seconds: seconds),
            title: "Position hold", subtitle: "Continuing")
    }
}

@MainActor
private final class PositionHoldTestDriver: ContinuedProcessingDriving {
    private var eventHandler: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
    private(set) var submitCount = 0
    private(set) var finishCalls = 0

    func register() -> Bool { true }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        submitCount += 1
        eventHandler = onEvent
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        finishCalls += 1
        return success ? .success : .failed
    }

    func cancel(requestID: UUID) {}

    func launch(_ request: ContinuedProcessingRequest) {
        eventHandler?(.launched(ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)))
    }
}
