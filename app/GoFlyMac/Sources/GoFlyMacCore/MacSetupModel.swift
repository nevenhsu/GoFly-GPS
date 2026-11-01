import Foundation
import Observation

public struct MacSetupTransactionIdentity: Equatable, Sendable {
    public let setupID: UUID
    public let deviceID: String
    public let mode: MacSetupMode
    public let transport: ConnectedDevice.Transport
    public let teamID: String

    public init(setupID: UUID, deviceID: String, mode: MacSetupMode = .install,
                transport: ConnectedDevice.Transport = .usb, teamID: String) throws {
        let normalized = deviceID.lowercased()
        guard setupFullMatch(normalized, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$"),
              MacBundleIdentifier.forTeamID(teamID) != nil,
              mode != .install || transport == .usb else {
            throw MacSetupFailure.invalidResponse
        }
        self.setupID = setupID
        self.deviceID = normalized
        self.mode = mode
        self.transport = transport
        self.teamID = teamID
    }
}

public enum MacAutoRenewState: Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
    case cancelled
}

public struct MacSetupJournalState: Sendable, Equatable {
    public let pendingTransaction: MacSetupTransactionIdentity?
    public let pendingSnapshot: MacSetupSnapshot?
    public let completed: MacSetupSnapshot?
    public init(pendingTransaction: MacSetupTransactionIdentity?, pendingSnapshot: MacSetupSnapshot? = nil,
                completed: MacSetupSnapshot?) {
        self.pendingTransaction = pendingTransaction; self.pendingSnapshot = pendingSnapshot; self.completed = completed
    }
}

public protocol MacSetupJournalReading: Sendable {
    func readPendingTransaction() async throws -> MacSetupTransactionIdentity?
    func readState() async throws -> MacSetupJournalState
}

public extension MacSetupJournalReading {
    func readState() async throws -> MacSetupJournalState {
        MacSetupJournalState(pendingTransaction: try await readPendingTransaction(), completed: nil)
    }
}

@MainActor @Observable
public final class MacSetupModel {
    public private(set) var pendingTransaction: MacSetupTransactionIdentity?
    public private(set) var snapshot: MacSetupSnapshot?
    public private(set) var lastCompleted: MacSetupSnapshot?
    public private(set) var progressStage: MacSetupStage?
    public private(set) var failure: MacSetupFailure?
    public private(set) var isBusy = false
    public private(set) var cancellationRequested = false
    public private(set) var isRestored = false
    public private(set) var isAutomaticRenewal = false
    public private(set) var autoRenewState: MacAutoRenewState = .idle
    public private(set) var options: MacSetupOptions?
    public private(set) var mode: MacSetupMode = .install
    @ObservationIgnored private var applyAfterPreflight = false
    @ObservationIgnored private let runner: any MacSetupRunning
    @ObservationIgnored private let journal: any MacSetupJournalReading
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var journalBlocked = false
    @ObservationIgnored private var journalIdentity: MacSetupTransactionIdentity?
    @ObservationIgnored private var previousCompletedIdentity: MacSetupTransactionIdentity?
    @ObservationIgnored private var restartSourceIdentity: MacSetupTransactionIdentity?
    @ObservationIgnored private var setAsideIdentity: MacSetupTransactionIdentity?

    public init(runner: any MacSetupRunning, journal: any MacSetupJournalReading) {
        self.runner = runner
        self.journal = journal
    }

    public var canApply: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity == nil && options != nil &&
            snapshot?.stage == .preflight && snapshot?.outcome == .ready && failure == nil
    }
    public var hasRecordedTransaction: Bool { journalIdentity != nil }
    public var hasUnfinishedTransaction: Bool {
        journalIdentity != nil && snapshot?.canReplaceCompletedTransaction != true
    }
    public var locksDevice: Bool { isBusy || journalBlocked || hasUnfinishedTransaction }
    /// An unfinished transaction locks only its own phone; another phone may
    /// still be listed and chosen (§5.4).
    public var locksOtherDevices: Bool { isBusy || journalBlocked }

    /// Sets the unfinished D14 projection aside so another phone can start
    /// fresh. The durable journal stays; the producer abandons it on the next
    /// apply, and a relaunch before then shows D14 again.
    public func setAsideUnfinished() {
        guard isRestored, !isBusy, !journalBlocked, hasUnfinishedTransaction else { return }
        setAsideIdentity = journalIdentity
        journalIdentity = nil
        restartSourceIdentity = nil
        pendingTransaction = nil
        options = nil
        snapshot = nil
        progressStage = nil
        failure = nil
        mode = .install
        applyAfterPreflight = false
        isAutomaticRenewal = false
        autoRenewState = .idle
    }

    public func resetSelection() {
        guard isRestored, !isBusy, !journalBlocked,
              journalIdentity == nil || snapshot?.canReplaceCompletedTransaction == true else { return }
        if let journalIdentity { previousCompletedIdentity = journalIdentity }
        journalIdentity = nil
        // Retire only the completed UI projection. The producer alone may
        // archive a fully validated completed journal under its global lock.
        pendingTransaction = nil
        options = nil
        snapshot = nil
        progressStage = nil
        failure = nil
        mode = .install
        applyAfterPreflight = false
        isAutomaticRenewal = false
        autoRenewState = .idle
    }
    public func restore() async {
        guard !isRestored, !isBusy else { return }
        isBusy = true
        await readJournal()
        isRestored = true
        isBusy = false
    }
    /// A failed journal read blocks every action.  Re-read it so a transient
    /// failure (for example a slow first Bridge launch) does not strand the
    /// user until the app is restarted.
    public func retryBlockedJournal() async {
        guard journalBlocked, !isBusy else { return }
        isBusy = true
        failure = nil
        await readJournal()
        isRestored = true
        isBusy = false
    }
    public func configure(deviceID: String, options: MacSetupOptions, mode: MacSetupMode = .install,
                          transport: ConnectedDevice.Transport = .usb) throws {
        guard isRestored, !isBusy, !journalBlocked else { throw MacSetupFailure.invalidResponse }
        guard journalIdentity == nil || snapshot?.canReplaceCompletedTransaction == true else {
            throw MacSetupFailure.service("transaction-conflict")
        }
        pendingTransaction = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: deviceID, mode: mode,
                                                transport: transport, teamID: options.teamID)
        journalIdentity = nil
        restartSourceIdentity = nil
        self.options = options
        self.mode = mode
        isAutomaticRenewal = false
        autoRenewState = .idle
        snapshot = nil
        progressStage = nil
        failure = nil
    }
    public func preflight() {
        guard journalIdentity == nil, options != nil else { return }
        // Pressing Install or Start over is the user's go-ahead; a ready
        // preflight continues straight into apply (§5.1, §5.4).
        applyAfterPreflight = true
        start(.preflight)
    }
    public func beginRenew(deviceID: String, options: MacSetupOptions,
                           transport: ConnectedDevice.Transport = .usb,
                           automatic: Bool = false) throws {
        if snapshot?.canReplaceCompletedTransaction == true { resetSelection() }
        try configure(deviceID: deviceID, options: options, mode: .renew, transport: transport)
        isAutomaticRenewal = automatic
        autoRenewState = automatic ? .running : .idle
        preflight()
    }
    public func beginRestart(deviceID: String, options: MacSetupOptions) throws {
        guard isRestored, !isBusy, !journalBlocked,
              let old = journalIdentity, snapshot?.canReplaceCompletedTransaction != true,
              old.deviceID == deviceID.lowercased(), old.teamID == options.teamID else {
            throw MacSetupFailure.service("transaction-conflict")
        }
        restartSourceIdentity = old
        pendingTransaction = try MacSetupTransactionIdentity(
            setupID: UUID(), deviceID: old.deviceID, mode: old.mode, transport: old.transport,
            teamID: old.teamID
        )
        journalIdentity = nil
        self.options = options
        mode = old.mode
        isAutomaticRenewal = false
        autoRenewState = .idle
        snapshot = nil
        progressStage = nil
        failure = nil
        preflight()
    }
    public func apply() {
        guard canApply else { return }
        start(.apply)
    }
    public func status() {
        guard journalIdentity != nil else { return }
        start(.status)
    }
    public func cancel() {
        guard isBusy, let task else { return }
        cancellationRequested = true
        task.cancel()
        progressTask?.cancel()
        // Keep both the task and admission fence until the process has returned.
    }

    private func start(_ action: MacSetupAction) {
        guard isRestored, !isBusy, !journalBlocked, let identity = pendingTransaction else { return }
        let request: MacSetupRequest
        do {
            request = try MacSetupRequest(action: action, setupID: identity.setupID, deviceID: identity.deviceID,
                                          mode: mode, transport: identity.transport,
                                          options: action == .preflight || action == .apply ? options : nil,
                                          teamID: identity.teamID)
        } catch {
            failure = error as? MacSetupFailure ?? .invalidRequest
            return
        }
        isBusy = true
        cancellationRequested = false
        snapshot = nil
        progressStage = nil
        failure = nil
        if action == .apply {
            progressTask = Task { await observeProgress(identity) }
        }
        task = Task {
            var observed: MacSetupSnapshot?
            var operationFailure: MacSetupFailure?
            do {
                let data = try await runner.run(request)
                try Task.checkCancellation()
                observed = try MacSetupResponseDecoder.decode(data, for: request)
                operationFailure = observed?.failure
            } catch {
                operationFailure = Task.isCancelled ? .cancelled : (error as? MacSetupFailure ?? .invalidResponse)
            }
            let observing = progressTask
            observing?.cancel()
            await observing?.value
            progressTask = nil
            if action == .preflight, let observed, observed.stage == .preflight,
               observed.outcome == .ready, observed.errorCode == nil, applyAfterPreflight, !Task.isCancelled {
                applyAfterPreflight = false
                snapshot = observed
                isBusy = false
                task = nil
                apply()
                return
            }
            if action == .preflight, observed?.errorCode == "app-already-installed",
               restartSourceIdentity?.mode == .install, mode == .install,
               let identity = pendingTransaction {
                do {
                    pendingTransaction = try MacSetupTransactionIdentity(
                        setupID: identity.setupID, deviceID: identity.deviceID,
                        mode: .renew, transport: identity.transport, teamID: identity.teamID
                    )
                    mode = .renew
                    snapshot = nil
                    failure = nil
                    isBusy = false
                    task = nil
                    preflight()
                    return
                } catch {
                    operationFailure = error as? MacSetupFailure ?? .invalidResponse
                }
            }
            applyAfterPreflight = false
            if action != .preflight || Task.isCancelled {
                do {
                    let actual = try await journal.readPendingTransaction()
                    if let actual, actual != identity {
                        let rejectedBeforeJournal = action == .apply && observed?.failure != nil
                            && observed?.stage == .preflight && observed?.installationConfirmed == false
                            && observed?.pairingImported == false && observed?.supportObserved == false
                        if actual == setAsideIdentity, rejectedBeforeJournal {
                            // The other phone's unfinished record is untouched;
                            // keep this phone's own retryable failure.
                            operationFailure = observed?.failure
                        } else if actual == restartSourceIdentity, rejectedBeforeJournal {
                            journalIdentity = actual
                            pendingTransaction = actual
                            options = nil
                            restartSourceIdentity = nil
                            operationFailure = observed?.failure
                        } else {
                            guard actual == previousCompletedIdentity else { throw MacSetupFailure.invalidResponse }
                            journalIdentity = actual
                            pendingTransaction = actual
                            options = nil
                            restartSourceIdentity = nil
                            observed = nil
                            operationFailure = .service("transaction-conflict")
                        }
                    } else {
                        if let observed, action != .preflight, actual == nil {
                            // Two outcomes legitimately leave nothing pending: the producer
                            // rejected apply before creating its transaction (retryable), or
                            // a confirmed apply left a completed journal, which reads as
                            // "nothing pending" and must hold the receipt just reported.
                            // Anything else is an integrity failure.
                            var recorded = false
                            if action == .apply, observed.canReplaceCompletedTransaction {
                                let durable = try await journal.readState().completed
                                recorded = durable?.receiptSHA256 == observed.receiptSHA256
                                    && durable?.appBuild == observed.appBuild
                            }
                            let rejectedBeforeJournal = action == .apply && observed.failure != nil
                                && observed.stage == .preflight && !observed.installationConfirmed
                                && !observed.pairingImported && !observed.supportObserved
                            guard recorded || rejectedBeforeJournal else {
                                throw MacSetupFailure.invalidResponse
                            }
                        }
                        journalIdentity = actual
                        if actual != nil {
                            options = nil
                            previousCompletedIdentity = nil
                            if actual == identity { restartSourceIdentity = nil; setAsideIdentity = nil }
                        }
                    }
                } catch {
                    journalBlocked = true
                    observed = nil
                    operationFailure = error as? MacSetupFailure ?? .invalidResponse
                }
            }
            if cancellationRequested {
                observed = nil
                if !journalBlocked { operationFailure = .cancelled }
            }
            snapshot = observed
            if observed?.isComplete == true { lastCompleted = observed }
            if isAutomaticRenewal {
                if observed?.isComplete == true {
                    autoRenewState = .completed
                } else if operationFailure == .cancelled {
                    autoRenewState = .cancelled
                } else if operationFailure != nil || observed?.outcome == .unknown || observed?.outcome == .failed {
                    autoRenewState = .failed
                }
            }
            progressStage = nil
            failure = operationFailure
            isBusy = false
            cancellationRequested = false
            task = nil
        }
    }

    private func observeProgress(_ identity: MacSetupTransactionIdentity) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            do {
                guard !Task.isCancelled else { return }
                guard try await journal.readPendingTransaction() == identity else { continue }
                let request = try MacSetupRequest(action: .status, setupID: identity.setupID,
                                                  deviceID: identity.deviceID, mode: mode,
                                                  transport: identity.transport,
                                                  teamID: identity.teamID)
                let data = try await runner.run(request)
                let observed = try MacSetupResponseDecoder.decode(data, for: request)
                guard !Task.isCancelled, isBusy, pendingTransaction == identity else { return }
                // A read-only journal observation supplies the stage only. It
                // cannot complete or release the still-running apply.
                progressStage = observed.stage
            } catch {
                if Task.isCancelled { return }
                progressStage = nil
            }
        }
    }

    private func readJournal() async {
        do {
            let state = try await journal.readState()
            lastCompleted = state.completed
            journalIdentity = state.pendingTransaction
            pendingTransaction = state.pendingTransaction
            mode = state.pendingTransaction?.mode ?? state.completed?.mode ?? .install
            options = nil
            snapshot = state.pendingSnapshot ?? state.completed
            journalBlocked = false
        } catch {
            journalBlocked = true
            failure = error as? MacSetupFailure ?? .invalidResponse
        }
    }
}
