import Combine
import Foundation

@MainActor
public final class ContinuedProcessingController: ObservableObject {
    @Published public private(set) var state: ContinuedProcessingState = .idle
    @Published public private(set) var currentRequest: ContinuedProcessingRequest?
    @Published public private(set) var grant: ContinuedProcessingGrant?
    @Published public private(set) var progress: ContinuedProcessingProgress = .zero
    @Published public private(set) var completionOutcome: ContinuedProcessingCompletionOutcome?
    @Published public private(set) var error: ContinuedProcessingFailure?
    @Published public private(set) var receipts: [ContinuedProcessingReceipt] = []

    private let driver: any ContinuedProcessingDriving
    private let now: @Sendable () -> Date
    private let onRuntimeAvailable: @MainActor @Sendable (ContinuedProcessingGrant) -> Void
    private let onRuntimeUnavailable: @MainActor @Sendable (UUID, ContinuedProcessingRuntimeLoss) -> Void
    private var registrationResult: Bool?
    private var generation: UInt64 = 0
    private var currentTitle = ""
    private var currentSubtitle = ""
    private var runtimeLossPublished = false

    public init(driver: any ContinuedProcessingDriving,
                now: @escaping @Sendable () -> Date = { Date() },
                onRuntimeAvailable: @escaping @MainActor @Sendable (ContinuedProcessingGrant) -> Void = { _ in },
                onRuntimeUnavailable: @escaping @MainActor @Sendable (UUID, ContinuedProcessingRuntimeLoss) -> Void = { _, _ in }) {
        self.driver = driver
        self.now = now
        self.onRuntimeAvailable = onRuntimeAvailable
        self.onRuntimeUnavailable = onRuntimeUnavailable
    }

    public var hasRuntime: Bool {
        guard state == .running, let request = currentRequest, let grant else { return false }
        return grant.isValid && grant.requestID == request.requestID &&
            grant.movementID == request.movementID && grant.lease == request.lease
    }

    @discardableResult
    public func register() -> Bool {
        if let registrationResult { return registrationResult }
        let result = driver.register()
        registrationResult = result
        guard result else {
            error = .registrationFailed
            if currentRequest == nil { state = .rejected }
            return false
        }
        return true
    }

    public func begin(_ request: ContinuedProcessingRequest, isForeground: Bool) async -> Bool {
        guard registrationResult == true else {
            rejectWithoutReplacement(.registrationFailed)
            return false
        }
        guard isForeground else {
            rejectWithoutReplacement(.notForeground)
            return false
        }

        supersedeCurrentIfNeeded()
        guard generation < UInt64.max else {
            state = .rejected
            error = .submissionRejected
            return false
        }
        generation += 1
        let submissionGeneration = generation
        currentRequest = request
        currentTitle = request.title
        currentSubtitle = request.subtitle
        progress = .zero
        grant = nil
        completionOutcome = nil
        error = nil
        runtimeLossPublished = false
        state = .submitting
        appendReceipt(for: request, event: .submitted)
        diagnose("background.submit", category: .background, level: .notice, [
            "kind": .text(request.kind.rawValue),
            "goal": .text(goalLabel(request.goal)),
            "request": .text(request.requestID.uuidString)
        ])

        let eventHandler: @MainActor @Sendable (ContinuedProcessingEvent) -> Void = { [weak self] event in
            self?.receive(event, generation: submissionGeneration)
        }
        return await withTaskCancellationHandler(operation: {
            do {
                try await driver.submit(request, onEvent: eventHandler)
                guard !Task.isCancelled else {
                    cancelGeneration(submissionGeneration, reason: .cancelled)
                    return false
                }
                return acceptSubmission(submissionGeneration, request: request)
            } catch is CancellationError {
                cancelGeneration(submissionGeneration, reason: .cancelled)
                return false
            } catch let failure as ContinuedProcessingFailure {
                rejectSubmission(submissionGeneration, request: request, failure: failure)
                return false
            } catch {
                rejectSubmission(submissionGeneration, request: request, failure: .submissionRejected)
                return false
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelGeneration(submissionGeneration, reason: .cancelled)
            }
        })
    }

    @discardableResult
    public func update(requestID: UUID, progress newProgress: ContinuedProcessingProgress,
                       title: String, subtitle: String) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              state == .submitting || state == .accepted || state == .running,
              ContinuedProcessingRequest.isValidPresentation(title, maximumUTF8Bytes: 128),
              ContinuedProcessingRequest.isValidPresentation(subtitle, maximumUTF8Bytes: 512),
              isProgressAllowed(newProgress, for: request) else { return false }

        if state == .running {
            guard let grant, grant.isValid,
                  grant.requestID == request.requestID, grant.movementID == request.movementID,
                  grant.lease == request.lease else { return false }
        }

        let sameProgress = progress == newProgress
        let samePresentation = currentTitle == title && currentSubtitle == subtitle
        guard !sameProgress || !samePresentation else { return true }
        self.progress = newProgress
        currentTitle = title
        currentSubtitle = subtitle
        appendReceipt(for: request, event: .progressUpdated)

        guard state == .running, let grant, grant.isValid,
              grant.requestID == request.requestID, grant.movementID == request.movementID,
              grant.lease == request.lease else {
            return state != .running
        }
        driver.update(requestID: requestID, progress: newProgress, title: title, subtitle: subtitle)
        return true
    }

    @discardableResult
    public func finishFiniteArrival(requestID: UUID) -> Bool {
        guard currentRequest?.requestID == requestID,
              currentRequest?.kind == .finiteRoute else { return false }
        return finishFiniteTask(requestID: requestID)
    }

    @discardableResult
    public func finishFiniteTask(requestID: UUID) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              finiteGoalReached(request),
              state == .submitting || state == .accepted || state == .running else { return false }

        let oldGeneration = retireGeneration()
        let hadGrant = grant != nil
        guard hadGrant else {
            driver.cancel(requestID: requestID)
            state = .finished
            error = .cancelled
            appendReceipt(for: request, event: .cancelRequested)
            return false
        }

        let outcome = driver.finish(requestID: requestID, success: true)
        grant?.revoke()
        appendReceipt(for: request, event: .completionRequested(outcome))
        switch outcome {
        case .success:
            completionOutcome = .success
            error = nil
            state = .finished
            return true
        case .expired:
            completionOutcome = .expired
            state = .expired
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .expired)
            return false
        case .cancelled:
            completionOutcome = .cancelled
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .cancelled)
            return false
        case .invalidated:
            completionOutcome = .invalidated
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .invalidated)
            return false
        case .failed:
            completionOutcome = .failed
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .invalidated)
            return false
        case nil:
            driver.cancel(requestID: requestID)
            state = .finished
            error = .cancelled
            return false
        }
    }

    @discardableResult
    public func cancel(requestID: UUID, asCompleted: Bool = false) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              state == .submitting || state == .accepted || state == .running else { return false }
        let hadGrant = grant != nil
        let oldGeneration = retireGeneration()
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .cancelRequested)
        diagnose("background.cancel", category: .background, level: .notice,
                 ["request": .text(requestID.uuidString), "hadGrant": .flag(hadGrant),
                  "asCompleted": .flag(asCompleted)])
        if asCompleted { driver.retire(requestID: requestID) } else { driver.cancel(requestID: requestID) }
        if hadGrant {
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .cancelled)
        }
        return true
    }

    private func receive(_ event: ContinuedProcessingEvent, generation eventGeneration: UInt64) {
        guard eventGeneration == generation else {
            if case .launched(let incomingGrant) = event, incomingGrant !== grant { incomingGrant.revoke() }
            return
        }
        guard let request = currentRequest else {
            if case .launched(let incomingGrant) = event, incomingGrant !== grant { incomingGrant.revoke() }
            return
        }
        switch event {
        case .launched(let incomingGrant):
            guard incomingGrant.requestID == request.requestID,
                  incomingGrant.movementID == request.movementID,
                  incomingGrant.lease == request.lease,
                  incomingGrant.isValid,
                  state == .submitting || state == .accepted || state == .running else {
                incomingGrant.revoke()
                return
            }
            if let existingGrant = grant {
                if existingGrant === incomingGrant { return }
                incomingGrant.revoke()
                return
            }
            grant = incomingGrant
            state = .running
            appendReceipt(for: request, event: .launched)
            diagnose("background.launched", category: .background, level: .notice, [
                "request": .text(request.requestID.uuidString),
                "kind": .text(request.kind.rawValue)
            ])
            let bufferedProgress = progress
            let bufferedTitle = currentTitle
            let bufferedSubtitle = currentSubtitle
            onRuntimeAvailable(incomingGrant)
            guard generation == eventGeneration, currentRequest?.requestID == request.requestID,
                  state == .running, let grant, grant === incomingGrant, grant.isValid,
                  grant.movementID == request.movementID, grant.lease == request.lease else { return }
            // A synchronous owner callback may have forwarded a newer real
            // progress/text value through update(). Do not forward it twice.
            if progress == bufferedProgress, currentTitle == bufferedTitle,
               currentSubtitle == bufferedSubtitle,
               progress != .zero || currentTitle != request.title || currentSubtitle != request.subtitle {
                driver.update(requestID: request.requestID, progress: progress,
                              title: currentTitle, subtitle: currentSubtitle)
            }
        case .expired(let requestID):
            guard requestID == request.requestID,
                  state == .submitting || state == .accepted || state == .running else { return }
            grant?.revoke()
            state = .expired
            completionOutcome = .expired
            appendReceipt(for: request, event: .expired)
            diagnose("background.expired", category: .background, level: .notice, [
                "request": .text(request.requestID.uuidString),
                "writes": .count(Int(progress.acknowledgedWrites)),
                "distance_m": .number(progress.cumulativeAcknowledgedDistanceMeters, digits: 1)
            ])
            publishRuntimeLoss(requestID: requestID, generation: eventGeneration, reason: .expired)
        case .invalidated(let requestID):
            guard requestID == request.requestID,
                  state == .submitting || state == .accepted || state == .running else { return }
            grant?.revoke()
            state = .finished
            completionOutcome = .invalidated
            appendReceipt(for: request, event: .invalidated)
            diagnose("background.invalidated", category: .background, level: .notice,
                     ["request": .text(request.requestID.uuidString)])
            publishRuntimeLoss(requestID: requestID, generation: eventGeneration, reason: .invalidated)
        }
    }

    private func acceptSubmission(_ eventGeneration: UInt64, request: ContinuedProcessingRequest) -> Bool {
        guard eventGeneration == generation, currentRequest?.requestID == request.requestID,
              state == .submitting || state == .accepted || state == .running else { return false }
        appendReceipt(for: request, event: .accepted)
        if state == .submitting { state = .accepted }
        return state == .accepted || state == .running
    }

    private func rejectSubmission(_ eventGeneration: UInt64, request: ContinuedProcessingRequest,
                                  failure: ContinuedProcessingFailure) {
        guard eventGeneration == generation, currentRequest?.requestID == request.requestID,
              state == .submitting || state == .accepted || state == .running else { return }
        let hadGrant = grant != nil
        let retiredGeneration = retireGeneration()
        grant?.revoke()
        state = .rejected
        error = failure
        appendReceipt(for: request, event: .rejected(failure))
        diagnose("background.submitRejected", category: .background, level: .error,
                 ["failure": .text(String(describing: failure))])
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: retiredGeneration, reason: .submissionRejected) }
    }

    private func rejectWithoutReplacement(_ failure: ContinuedProcessingFailure) {
        guard state == .submitting || state == .accepted || state == .running else {
            state = .rejected
            error = failure
            return
        }
        error = failure
    }

    private func supersedeCurrentIfNeeded() {
        guard let request = currentRequest,
              state == .submitting || state == .accepted || state == .running else { return }
        let oldGeneration = retireGeneration()
        let hadGrant = grant != nil
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .superseded)
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: oldGeneration, reason: .superseded) }
    }

    private func cancelGeneration(_ eventGeneration: UInt64, reason: ContinuedProcessingRuntimeLoss) {
        guard eventGeneration == generation, let request = currentRequest,
              state == .submitting || state == .accepted || state == .running else { return }
        let hadGrant = grant != nil
        let retiredGeneration = retireGeneration()
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .cancelRequested)
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: retiredGeneration, reason: reason) }
    }

    private func isProgressAllowed(_ candidate: ContinuedProcessingProgress,
                                   for request: ContinuedProcessingRequest) -> Bool {
        guard candidate.acknowledgedWrites >= progress.acknowledgedWrites,
              candidate.cumulativeAcknowledgedDistanceMeters >= progress.cumulativeAcknowledgedDistanceMeters,
              candidate.cumulativeAcknowledgedDurationSeconds >= progress.cumulativeAcknowledgedDurationSeconds else { return false }
        if case .finiteDistance(let goal) = request.goal {
            return candidate.cumulativeAcknowledgedDistanceMeters <= goal
        }
        if case .finiteDuration(let goal) = request.goal {
            return candidate.cumulativeAcknowledgedDurationSeconds <= goal
        }
        return true
    }

    private func finiteGoalReached(_ request: ContinuedProcessingRequest) -> Bool {
        switch (request.kind, request.goal) {
        case (.finiteRoute, .finiteDistance(let goal)):
            return progress.cumulativeAcknowledgedDistanceMeters == goal
        case (.fixedPosition, .finiteDuration(let goal)):
            return progress.cumulativeAcknowledgedDurationSeconds == goal
        case (.roundTrip, .finiteDuration(let goal)):
            return progress.cumulativeAcknowledgedDurationSeconds == goal
        case (.wander, .finiteDuration(let goal)):
            return progress.cumulativeAcknowledgedDurationSeconds == goal
        default:
            return false
        }
    }

    private func publishRuntimeLoss(requestID: UUID, generation eventGeneration: UInt64,
                                    reason: ContinuedProcessingRuntimeLoss) {
        guard eventGeneration == generation || (eventGeneration < UInt64.max && eventGeneration + 1 == generation),
              !runtimeLossPublished else { return }
        runtimeLossPublished = true
        onRuntimeUnavailable(requestID, reason)
    }

    @discardableResult
    private func retireGeneration() -> UInt64 {
        let retired = generation
        if generation < UInt64.max { generation += 1 }
        return retired
    }

    private func appendReceipt(for request: ContinuedProcessingRequest,
                               event: ContinuedProcessingReceiptEvent) {
        let receipt = ContinuedProcessingReceipt(timestamp: now(), requestID: request.requestID,
                                                 kind: request.kind, event: event, progress: progress)
        receipts.append(receipt)
        if receipts.count > 256 { receipts.removeFirst(receipts.count - 256) }
    }
}

private func goalLabel(_ goal: ContinuedProcessingGoal) -> String {
    switch goal {
    case .finiteDistance(let meters): "finite:\(DiagnosticsField.fixed(meters, 0))m"
    case .finiteDuration(let seconds): "finite:\(DiagnosticsField.fixed(seconds, 0))s"
    case .experimentalIndeterminate: "indeterminate"
    }
}

private func diagnose(_ name: String, category: DiagnosticsCategory, level: DiagnosticsLevel = .debug,
                      _ fields: [String: DiagnosticsField] = [:]) {
    Diagnostics.shared.record(name, category: category, level: level, fields)
}
