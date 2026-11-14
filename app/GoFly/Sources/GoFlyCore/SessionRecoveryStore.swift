import Combine
import Foundation

private actor SessionRecoveryWriter {
    private let persistence: any SessionRecoveryPersistence
    private var encodedGPX: (document: GPXDocument, data: Data)?

    init(persistence: any SessionRecoveryPersistence) {
        self.persistence = persistence
    }

    /// Encoding and the synchronous filesystem transaction run on this actor,
    /// never on the MainActor. The store owns the single pending slot and calls
    /// this method from its one drain task, so the actor never receives an
    /// unbounded enqueue stream.
    func write(revision: UInt64, snapshot: SessionRecoverySnapshot) -> Result<Void, SessionRecoveryFailure> {
        do {
            let data = try SessionRecoveryCodec.encode(snapshot, revision: revision) { document in
                if let encodedGPX, encodedGPX.document == document { return encodedGPX.data }
                let data = try GPXCodec.encode(document)
                encodedGPX = (document, data)
                return data
            }
            try persistence.replaceAtomically(with: data)
            return .success(())
        } catch let failure as SessionRecoveryFailure {
            return .failure(failure)
        } catch {
            return .failure(.writeFailed)
        }
    }
}

@MainActor
public final class SessionRecoveryStore: ObservableObject {
    public let initialSnapshot: SessionRecoverySnapshot

    @Published public private(set) var loadState: SessionRecoveryLoadState
    @Published public private(set) var error: SessionRecoveryFailure?
    @Published public private(set) var isSaving = false
    @Published public private(set) var hasUnsavedChanges = false

    private let persistence: any SessionRecoveryPersistence
    private let writer: SessionRecoveryWriter
    private var latestSnapshot: SessionRecoverySnapshot?
    private var latestRevision: UInt64
    private var lastCommittedRevision: UInt64
    private var highestSubmittedRevision: UInt64 = 0
    private var pendingWrite: (revision: UInt64, snapshot: SessionRecoverySnapshot)?
    private var drainTask: Task<Void, Never>?
    private var lastTerminalRevision: UInt64?
    private var lastTerminalResult: Result<Void, SessionRecoveryFailure>?
    private var invalidLatest = false
    private var waiters: [(id: UUID, target: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []

    public init(persistence: any SessionRecoveryPersistence) {
        self.persistence = persistence
        let loaded: (snapshot: SessionRecoverySnapshot, revision: UInt64)?
        let state: SessionRecoveryLoadState
        let failure: SessionRecoveryFailure?
        do {
            if let data = try persistence.read() {
                let record = try SessionRecoveryCodec.decodeRecord(data)
                loaded = record
                state = .ready
                failure = nil
            } else {
                loaded = nil
                state = .ready
                failure = nil
            }
        } catch let error as SessionRecoveryFailure {
            loaded = nil
            state = .blocked(error)
            failure = error
        } catch {
            loaded = nil
            state = .blocked(.unavailable)
            failure = .unavailable
        }
        self.initialSnapshot = loaded?.snapshot ?? SessionRecoverySnapshot()
        self.latestSnapshot = loaded?.snapshot
        self.latestRevision = loaded?.revision ?? 0
        self.lastCommittedRevision = loaded?.revision ?? 0
        self.loadState = state
        self.error = failure
        self.writer = SessionRecoveryWriter(persistence: persistence)
    }

    /// Synchronous admission into the bounded writer. `true` means the snapshot
    /// was accepted into memory and queued; it does not mean bytes are durable.
    @discardableResult
    public func capture(_ snapshot: SessionRecoverySnapshot) -> Bool {
        guard loadState == .ready else { return false }
        return acceptSnapshot(snapshot)
    }

    /// The admitted data-operation owner may persist the current accepted
    /// snapshot while all ordinary writers remain held. This token comes from
    /// this actual store; it does not grant service or movement authority.
    @discardableResult

    private func acceptSnapshot(_ snapshot: SessionRecoverySnapshot) -> Bool {
        guard latestRevision < UInt64.max else {
            block(.revisionExhausted)
            return false
        }
        let revision = latestRevision + 1
        // Consume the attempt revision before validation so an older in-flight
        // completion cannot clear the newer invalid-latest status.
        latestRevision = revision
        do { try SessionRecoveryCodec.validateSnapshot(snapshot) }
        catch let failure as SessionRecoveryFailure {
            invalidLatest = true
            latestSnapshot = nil
            hasUnsavedChanges = true
            error = failure
            return false
        } catch {
            invalidLatest = true
            latestSnapshot = nil
            hasUnsavedChanges = true
            self.error = .invalidSnapshot
            return false
        }
        latestSnapshot = snapshot
        invalidLatest = false
        hasUnsavedChanges = true
        error = nil
        isSaving = true
        submit(revision: revision, snapshot: snapshot)
        return true
    }

    /// Waits for the revision accepted at invocation, or a newer writer result.
    /// Cancellation only releases this waiter; the atomic write continues.
    public func flush() async -> Bool {
        guard loadState == .ready, !invalidLatest else { return false }
        return await waitForLatestWrite()
    }

    /// Wait for the snapshot submitted by the same admitted owner without
    /// releasing its hold or admitting a normal capture in the meantime.

    private func waitForLatestWrite() async -> Bool {
        let target = latestRevision
        if target <= lastCommittedRevision { return true }
        if !isSaving {
            if let terminalRevision = lastTerminalRevision, terminalRevision >= target,
               let terminalResult = lastTerminalResult {
                return terminalResult.isSuccess
            }
            return false
        }
        if Task.isCancelled { return false }
        let id = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if lastCommittedRevision >= target {
                    continuation.resume(returning: true)
                } else {
                    waiters.append((id: id, target: target, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id) }
        })
    }

    /// Retries only the newest valid dirty snapshot. A blocked initial read and
    /// an invalid latest capture cannot be bypassed by replaying older bytes.
    @discardableResult
    public func retrySaving() -> Bool {
        guard loadState == .ready, !invalidLatest, !isSaving, hasUnsavedChanges,
              let snapshot = latestSnapshot else { return false }
        isSaving = true
        error = nil
        submit(revision: latestRevision, snapshot: snapshot)
        return true
    }

    public func clearError() { error = nil }

    /// Drops the historical active/uncertainty fields and waits for the empty
    /// snapshot to commit before the caller releases its cold-clear fence.
    public func clearMovementState() async -> Bool {
        guard loadState == .ready else { return false }
        let current = latestSnapshot ?? initialSnapshot
        let cleared = SessionRecoverySnapshot(mode: current.mode, draft: current.draft,
            roundTripEnabled: current.roundTripEnabled, joystickSpeed: current.joystickSpeed,
            position: current.position, activeMovement: nil, uncertainty: nil)
        guard capture(cleared) else { return false }
        return await flush()
    }


    @discardableResult

    private func submit(revision: UInt64, snapshot: SessionRecoverySnapshot) {
        highestSubmittedRevision = max(highestSubmittedRevision, revision)
        pendingWrite = (revision: revision, snapshot: snapshot)
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            await self?.drainPendingWrites()
        }
    }

    private func drainPendingWrites() async {
        while let job = pendingWrite {
            pendingWrite = nil
            let result = await writer.write(revision: job.revision, snapshot: job.snapshot)
            writerCompleted(revision: job.revision, result: result)
        }
        drainTask = nil
    }

    private func writerCompleted(revision: UInt64, result: Result<Void, SessionRecoveryFailure>) {
        lastTerminalRevision = revision
        lastTerminalResult = result
        resolveWaiters(upTo: revision, result: result)
        // A newer invalid capture advances latestRevision without submitting a
        // job. Once the last submitted older job finishes, saving must stop
        // being reported as active while the invalid latest state stays dirty.
        if revision == highestSubmittedRevision { isSaving = false }
        guard revision == latestRevision else { return }
        switch result {
        case .success:
            lastCommittedRevision = revision
            hasUnsavedChanges = false
            error = nil
        case .failure(let failure):
            hasUnsavedChanges = true
            error = failure
            if failure == .invalidSnapshot || failure == .limitExceeded {
                invalidLatest = true
                latestSnapshot = nil
            }
        }
    }

    private func resolveWaiters(upTo revision: UInt64, result: Result<Void, SessionRecoveryFailure>) {
        guard !waiters.isEmpty else { return }
        let matching = waiters.filter { $0.target <= revision }
        waiters.removeAll { $0.target <= revision }
        for waiter in matching {
            waiter.continuation.resume(returning: result.isSuccess)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func block(_ failure: SessionRecoveryFailure) {
        loadState = .blocked(failure)
        error = failure
        isSaving = false
    }
}

private extension Result where Success == Void, Failure == SessionRecoveryFailure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
