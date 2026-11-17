import BackgroundTasks
import Foundation
import GoFlyCore

/// One process-owned BackgroundTasks adapter for the minimal continued task.
@available(iOS 26.0, *)
@MainActor
public final class GoFlyContinuedProcessingDriver: ContinuedProcessingDriving {
    public static let shared = GoFlyContinuedProcessingDriver()
    static let identifier = (Bundle.main.bundleIdentifier ?? "") + ".movement"

    private let scheduler = BGTaskScheduler.shared
    private var registrationResult: Bool?
    private var currentRequest: ContinuedProcessingRequest?
    private var currentTask: BGContinuedProcessingTask?
    private var eventHandler: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
    private var completion: ContinuedProcessingTaskCompletion?
    private var completed = false
    private var deliveredText: (title: String, subtitle: String)?

    private init() {}

    @discardableResult
    public func register() -> Bool {
        if let registrationResult { return registrationResult }
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        let result = permitted.contains(Self.identifier) &&
            scheduler.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
                MainActor.assumeIsolated { self?.receive(task) }
            }
        registrationResult = result
        return result
    }

    public func submit(_ request: ContinuedProcessingRequest,
                       onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        guard register() else { throw ContinuedProcessingFailure.registrationFailed }
        retireCurrent()
        currentRequest = request
        eventHandler = onEvent
        completed = false

        let taskRequest = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier, title: request.title, subtitle: request.subtitle)
        // Queue behind other continued-processing work instead of rejecting
        // the user's movement when iOS has no immediate task slot.
        taskRequest.strategy = .queue
        taskRequest.requiredResources = []
        do {
            if #available(iOS 27.0, *) { try await scheduler.submitTaskRequest(taskRequest) }
            else { try scheduler.submit(taskRequest) }
        } catch {
            Diagnostics.shared.record("background.submitFailed", category: .background, level: .error, [
                "request": .text(request.requestID.uuidString),
                "cancelled": .flag(error is CancellationError),
                "domain": .text((error as NSError).domain),
                "code": .count((error as NSError).code)
            ])
            if currentRequest?.requestID == request.requestID { clearCurrent() }
            throw error is CancellationError ? CancellationError() : ContinuedProcessingFailure.submissionRejected
        }
        guard currentRequest?.requestID == request.requestID else { throw CancellationError() }
        Diagnostics.shared.record("background.submitted", category: .background, level: .notice, [
            "request": .text(request.requestID.uuidString),
            "kind": .text(request.kind.rawValue),
            "strategy": .text("queue"),
            "ios27": .flag(ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
        ])
        if Task.isCancelled { cancel(requestID: request.requestID); throw CancellationError() }
    }

    public func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        guard let request = currentRequest, request.requestID == requestID, let currentTask,
              valid(title, 128), valid(subtitle, 512) else { return }
        let units = ContinuedProcessingProgressUnits.forRequest(request, progress: progress)
        let totalChanged = currentTask.progress.totalUnitCount != units.totalUnitCount
        let completedChanged = currentTask.progress.completedUnitCount != units.completedUnitCount
        if totalChanged { currentTask.progress.totalUnitCount = units.totalUnitCount }
        if completedChanged { currentTask.progress.completedUnitCount = units.completedUnitCount }
        if deliveredText?.title != title || deliveredText?.subtitle != subtitle {
            currentTask.updateTitle(title, subtitle: subtitle)
            deliveredText = (title, subtitle)
        }
        guard totalChanged || completedChanged else { return }
        Diagnostics.shared.record("background.progressUnits", category: .background, [
            "total": .count(Int(units.totalUnitCount)),
            "completed": .count(Int(units.completedUnitCount)),
            "writes": .count(Int(progress.acknowledgedWrites))
        ])
    }

    public func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        guard let request = currentRequest, request.requestID == requestID,
              Self.isFiniteGoal(request) else { return nil }
        let claim = completion?.claim(success ? .success : .failed)
        complete(success: claim?.outcome == .success)
        clearCurrent()
        return claim?.outcome
    }

    public func cancel(requestID: UUID) {
        guard currentRequest?.requestID == requestID else { return }
        _ = completion?.claim(.cancelled)
        complete(success: false)
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
        clearCurrent()
    }

    /// A countdown restart on return to the foreground: end a launched task
    /// as successful so iOS shows no "stopped" activity for it. A task that
    /// never launched still has to be withdrawn from the scheduler.
    public func retire(requestID: UUID) {
        guard currentRequest?.requestID == requestID else { return }
        _ = completion?.claim(.cancelled)
        if currentTask != nil { complete(success: true) }
        else { complete(success: false); scheduler.cancel(taskRequestWithIdentifier: Self.identifier) }
        clearCurrent()
    }

    private func receive(_ task: BGTask) {
        guard !completed, let request = currentRequest,
              let continued = task as? BGContinuedProcessingTask,
              continued.identifier == Self.identifier else {
            task.setTaskCompleted(success: false)
            return
        }
        let grant = ContinuedProcessingGrant(requestID: request.requestID,
                                             movementID: request.movementID, lease: request.lease)
        deliveredText = nil
        currentTask = continued
        completion = ContinuedProcessingTaskCompletion(grant: grant)
        Diagnostics.shared.record("background.taskLaunched", category: .background, level: .notice, [
            "request": .text(request.requestID.uuidString),
            "kind": .text(request.kind.rawValue)
        ])
        continued.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        eventHandler?(.launched(grant))
    }

    private func expire() {
        guard !completed else { return }
        Diagnostics.shared.record("background.taskExpired", category: .background, level: .notice, [
            "request": .text(currentRequest?.requestID.uuidString ?? "none"),
            "kind": .text(currentRequest?.kind.rawValue ?? "none")
        ])
        _ = completion?.claim(.expired)
        let requestID = currentRequest?.requestID
        complete(success: false)
        if let requestID { eventHandler?(.expired(requestID: requestID)) }
        clearCurrent()
    }

    private func complete(success: Bool) {
        guard !completed else { return }
        completed = true
        currentTask?.setTaskCompleted(success: success)
        currentTask?.expirationHandler = nil
        currentTask = nil
    }

    private func retireCurrent() {
        guard currentRequest != nil else { return }
        _ = completion?.claim(.cancelled)
        complete(success: false)
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
        clearCurrent()
    }

    private func clearCurrent() {
        deliveredText = nil
        currentRequest = nil
        currentTask = nil
        completion = nil
        eventHandler = nil
    }

    private func valid(_ value: String, _ maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            value.utf8.count <= maximum && !value.unicodeScalars.contains { $0.value == 0 }
    }

    private static func isFiniteGoal(_ request: ContinuedProcessingRequest) -> Bool {
        switch (request.kind, request.goal) {
        case (.finiteRoute, .finiteDistance),
             (.fixedPosition, .finiteDuration),
             (.roundTrip, .finiteDuration),
             (.wander, .finiteDuration):
            return true
        default:
            return false
        }
    }
}
