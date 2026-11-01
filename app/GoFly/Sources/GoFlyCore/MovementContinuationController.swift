import Combine
import Foundation

/// App lifecycle boundary for real user consent, accepted movement, and system runtime.
@MainActor
public final class MovementContinuationController: ObservableObject {
    public var state: ContinuedProcessingState { runtime?.state ?? .idle }
    @Published public private(set) var noticeKey: String?
    @Published public private(set) var receipts: [ContinuedProcessingReceipt] = []

    private struct Epoch {
        let demand: MovementContinuationDemand
        let origin: Double
        var lastSequence: UInt64?
        var count: Int64 = 0
        var distance: Double = 0
        var duration: Duration = .zero
        var lastAcknowledgedAt: Duration?
        /// Background entry time; duration only counts while this is set.
        var countingSince: Duration?

        /// Returning to the foreground cancels the countdown, not the movement.
        mutating func stopCountdown() {
            duration = .zero; lastAcknowledgedAt = nil; countingSince = nil
        }
        func matches(_ id: UUID, _ lease: MovementTaskLease) -> Bool {
            demand.movementID == id && demand.lease == lease
        }
        mutating func acknowledge(_ ack: MovementAcknowledgement, at now: Duration) -> Bool {
            guard matches(ack.movementID, ack.lease) else { return true }
            if let lastSequence, ack.sequence <= lastSequence { return true }
            guard count < Int64.max else { return false }
            let next: Double
            if demand.kind == .finiteRoute {
                guard let position = ack.routePositionMeters, position.isFinite else { return false }
                next = abs(position - origin)
            } else { next = distance + ack.acknowledgedDistanceMeters }
            guard next.isFinite, next >= 0 else { return false }
            if case .finiteDuration(let seconds) = demand.goal {
                let goal = Duration.seconds(seconds)
                if ack.source == .fixedPosition {
                    guard ack.cumulativeAcknowledgedDurationSeconds.isFinite,
                          ack.cumulativeAcknowledgedDurationSeconds >= 0,
                          ack.cumulativeAcknowledgedDurationSeconds <= seconds else { return false }
                    let nextDuration = Duration.seconds(ack.cumulativeAcknowledgedDurationSeconds)
                    guard nextDuration >= duration else { return false }
                    duration = nextDuration
                } else if let since = countingSince, let lastAcknowledgedAt, now >= lastAcknowledgedAt {
                    let interval = now - lastAcknowledgedAt
                    // A gap without ACKs is not evidence of active execution.
                    if interval <= .seconds(15), now > since {
                        duration = min(goal, duration + (now - max(lastAcknowledgedAt, since)))
                    }
                }
                lastAcknowledgedAt = now
            }
            count += 1; distance = next; lastSequence = ack.sequence
            return true
        }
        var progress: ContinuedProcessingProgress? {
            ContinuedProcessingProgress(acknowledgedWrites: count, cumulativeAcknowledgedDistanceMeters: distance,
                cumulativeAcknowledgedDurationSeconds: Double(duration.components.seconds)
                    + Double(duration.components.attoseconds) / 1e18)
        }
    }
    private struct Candidate {
        let request: ContinuedProcessingRequest
        var epoch: Epoch
        var boundGrant: ContinuedProcessingGrant?
    }
    private let service: ServiceController
    private let route: RouteExecutionController
    private let joystick: JoystickMovementController
    private let recovery: ConnectionRecoveryController
    private let positionHold: PositionHoldController?
    private let clock: any RouteClock
    private let presentation: @MainActor @Sendable (ContinuedProcessingKind, ContinuedProcessingProgress) -> (title: String, subtitle: String)
    private var runtime: ContinuedProcessingController!
    private var subscriptions: [AnyCancellable] = []
    private var sceneActive = false
    private var pending: Epoch?
    // The user's duration limit remains in force even if the framework never
    // launches or rejects its background request.
    private var durationEpoch: Epoch?
    private var candidate: Candidate?
    // Retain the physical submission until even an uncooperative callee returns.
    private var submitTask: Task<Void, Never>?
    private var submissionID: UUID?
    private var lastBlockedKey: String?
    private var lastAcknowledgement: MovementAcknowledgement?
    private var cleanupQueued = false
    private var handlingRuntimeLoss = false

    public init(service: ServiceController, route: RouteExecutionController,
                joystick: JoystickMovementController, recovery: ConnectionRecoveryController,
                positionHold: PositionHoldController? = nil,
                clock: any RouteClock = ContinuousRouteClock(),
                driver: any ContinuedProcessingDriving,
                presentation: @escaping @MainActor @Sendable (ContinuedProcessingKind, ContinuedProcessingProgress) -> (title: String, subtitle: String)) {
        self.service = service; self.route = route; self.joystick = joystick
        self.recovery = recovery; self.presentation = presentation
        self.positionHold = positionHold; self.clock = clock
        runtime = ContinuedProcessingController(driver: driver,
            onRuntimeAvailable: { [weak self] in self?.launched($0) },
            onRuntimeUnavailable: { [weak self] in self?.lostRuntime($0, $1) })
        service.setMovementSceneActive(false)
        recovery.releaseForInactiveScene()
        positionHold?.releaseForInactiveScene()
        installSubscriptions()
        // Configuration readiness, never SDK submission. Report this failure
        // once; routine UI relays must not resurrect a user-cleared notice.
        if !runtime.register() { noticeKey = failureNotice(runtime.error) }
        synchronize()
    }
    public var hasRuntime: Bool {
        guard let candidate, runtime.hasRuntime else { return false }
        return service.hasMovementContinuation(movementID: candidate.request.movementID,
            lease: candidate.request.lease, requestID: candidate.request.requestID)
    }
    public func sceneDidBecomeActive() {
        guard !sceneActive else { return }
        if let candidate, let grant = candidate.boundGrant, !grant.isValid {
            pauseForRuntimeLoss(candidate, notice: "background.expired")
        }
        sceneActive = true
        service.setMovementSceneActive(true)
        let countedInBackground = (candidate?.epoch.duration ?? .zero) > .zero
        durationEpoch?.stopCountdown()
        pending?.stopCountdown()
        candidate?.epoch.stopCountdown()
        positionHold?.sceneDidBecomeActive()
        recovery.sceneDidBecomeActive()
        restartDurationCountdown(force: countedInBackground)
        synchronize()
    }
    /// The user changed the background run time in Settings (foreground).
    public func backgroundDurationDidChange() {
        restartDurationCountdown(force: false)
        synchronize()
    }
    public func releaseForInactiveScene() {
        sceneActive = false
        diagnose("background.release", category: .background, level: .notice, [
            "candidate": .flag(candidate != nil),
            "pending": .flag(pending != nil),
            "state": .text(String(describing: runtime.state))
        ])
        service.setMovementSceneActive(false) // Fence before invoking any callbacks.
        let ungrantedCandidate = candidate
        let hadDemand = candidate != nil || pending != nil
        pending = nil
        let lease = hasRuntime && candidate.map({ ownerReady($0.epoch.demand) }) == true
            ? candidate?.request.lease : nil
        if lease == nil, let current = ungrantedCandidate {
            pauseForRuntimeLoss(current, notice: "background.unavailable")
        }
        if lease != nil {
            let now = clock.now
            durationEpoch?.countingSince = now
            candidate?.epoch.countingSince = now
        }
        recovery.releaseForInactiveScene(continuingLease: lease)
        positionHold?.releaseForInactiveScene(continuingLease: lease)
        if lease == nil { retireCurrent(reason: .ownerPausedOrEnded) }
        if lease == nil, hadDemand { noticeKey = "background.unavailable" }
        synchronize()
    }
    public func refreshPresentation() { forwardProgress(); synchronize() }

    private func installSubscriptions() {
        subscriptions = [
            service.$isRecoveringConnection.sink { [weak self] recovering in
                guard recovering, let self else { return }
                self.durationEpoch?.lastAcknowledgedAt = nil
                self.candidate?.epoch.lastAcknowledgedAt = nil
                self.pending?.lastAcknowledgedAt = nil
            },
            route.continuationControlEvents.sink { [weak self] in self?.control($0) },
            joystick.continuationControlEvents.sink { [weak self] in self?.control($0) },
            route.movementAcknowledgements.sink { [weak self] in self?.acknowledged($0) },
            service.movementAcknowledgements.sink { [weak self] ack in
                guard let self, self.positionHold?.intent?.id != ack.movementID else { return }
                self.acknowledged(ack)
            },
            service.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            route.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            joystick.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            runtime.objectWillChange.sink { [weak self] _ in self?.queueCleanup() },
            service.joystickEvents.sink { [weak self] event in
                guard case .movementBoundary(let lease) = event else { return }
                self?.movementBoundary(lease)
            }
        ]
        if let positionHold {
            subscriptions.append(positionHold.continuationControlEvents.sink { [weak self] in self?.control($0) })
            subscriptions.append(positionHold.movementAcknowledgements.sink { [weak self] in self?.acknowledged($0) })
            subscriptions.append(positionHold.objectWillChange.sink { [weak self] _ in self?.queueCleanup() })
        }
    }
    private func control(_ event: MovementContinuationControlEvent) {
        switch event {
        case .requested(let demand): requested(demand)
        case .withdrawn(let identity, let reason):
            if pending?.matches(identity.movementID, identity.lease) == true { pending = nil }
            if durationEpoch?.matches(identity.movementID, identity.lease) == true { durationEpoch = nil }
            if let current = candidate, current.epoch.matches(identity.movementID, identity.lease) {
                let retirement: MovementContinuationRetirement
                if case .automaticDisabled(manualInputContinues: true) = reason {
                    retirement = .foregroundManualAfterAutoOff
                } else { retirement = .ownerPausedOrEnded }
                retireCurrent(reason: retirement)
            }
            if !handlingRuntimeLoss {
                switch reason {
                case .userPaused:
                    noticeKey = positionHold?.intent?.id == identity.movementID && positionHold?.phase == .paused
                        ? "background.positionPaused" : nil
                case .userCancelled, .automaticDisabled: noticeKey = nil
                case .ended: break
                }
            }
            synchronize()
        }
    }
    /// A fresh background task for the next trip: the countdown starts at
    /// zero with the current run time. iOS only accepts submissions while the
    /// app is in the foreground, so this runs on return and on a setting change.
    private func restartDurationCountdown(force: Bool) {
        guard sceneActive, let current = candidate, current.boundGrant?.isValid != false,
              case .finiteDuration(let submitted) = current.request.goal else { return }
        let goal = current.request.kind == .fixedPosition
            ? positionHold?.durationGoalSeconds ?? BackgroundRunDuration.shared.seconds
            : BackgroundRunDuration.shared.seconds
        guard force || goal != submitted else { return }
        requested(MovementContinuationDemand(movementID: current.request.movementID,
            lease: current.request.lease, kind: current.request.kind,
            goal: .finiteDuration(seconds: goal)), restart: true)
    }
    private func requested(_ demand: MovementContinuationDemand, restart: Bool = false) {
        guard sceneActive else { return }
        noticeKey = nil
        if let current = candidate, current.epoch.matches(demand.movementID, demand.lease) {
            let stillBound = service.movementContinuationIsBound(
                requestID: current.request.requestID, lease: current.request.lease)
            if stillBound && current.boundGrant?.isValid != true {
                pending = nil; pauseForRuntimeLoss(current, notice: "background.expired"); return
            }
            if !restart, current.request.kind == demand.kind, current.request.goal == demand.goal,
               [.submitting, .accepted, .running].contains(runtime.state),
               current.boundGrant == nil || stillBound { return }
            // Successful explicit Resume has already retired its old binding.
            // A goal edit may retire only a still-valid concrete binding.
            if stillBound && !service.retireMovementContinuation(
                requestID: current.request.requestID, lease: current.request.lease,
                reason: .foregroundGoalChange) {
                pending = nil; pauseForRuntimeLoss(current, notice: "background.unavailable"); return
            }
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        let last = lastAcknowledgement.flatMap {
            $0.movementID == demand.movementID && $0.lease == demand.lease ? $0.sequence : nil
        }
        diagnose("background.demand", category: .background, level: .notice, [
            "kind": .text(demand.kind.rawValue),
            "hasGoal": .flag(demand.goal != nil),
            "movement": .text(demand.movementID.uuidString)
        ])
        pending = Epoch(demand: demand, origin: route.progress?.committedDistanceMeters ?? 0, lastSequence: last)
        if case .finiteDuration = demand.goal { durationEpoch = pending }
        if demand.goal == nil { pending = nil; synchronize(); return }
        drainPending()
    }
    private func acknowledged(_ ack: MovementAcknowledgement) {
        guard service.movementAuthority.snapshot.lease == ack.lease, sceneActive || hasRuntime else { return }
        if let last = lastAcknowledgement, last.movementID == ack.movementID,
           last.lease == ack.lease, ack.sequence <= last.sequence { return }
        guard ack.acknowledgedDistanceMeters.isFinite, ack.acknowledgedDistanceMeters >= 0 else {
            rejectInvalidProgress(); return
        }
        lastAcknowledgement = ack
        var completedDuration: MovementContinuationDemand?
        if var epoch = durationEpoch, epoch.matches(ack.movementID, ack.lease) {
            guard epoch.acknowledge(ack, at: clock.now) else { rejectInvalidProgress(); return }
            durationEpoch = epoch
            if case .finiteDuration(let goal) = epoch.demand.goal, epoch.duration == .seconds(goal) {
                completedDuration = epoch.demand
            }
        }
        if let current = candidate, !current.epoch.matches(ack.movementID, ack.lease) {
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        if var epoch = pending, epoch.matches(ack.movementID, ack.lease) {
            guard epoch.acknowledge(ack, at: clock.now) else { rejectInvalidProgress(); return }
            pending = epoch
        }
        if var current = candidate, current.epoch.matches(ack.movementID, ack.lease),
           current.boundGrant?.isValid != false {
            guard current.epoch.acknowledge(ack, at: clock.now) else { rejectInvalidProgress(); return }
            candidate = current
            forwardProgress()
            if ack.finiteArrival, current.request.kind == .finiteRoute,
               case .finiteDistance(let goal) = current.request.goal,
               current.epoch.distance == goal,
               runtime.finishFiniteArrival(requestID: current.request.requestID) { candidate = nil }
            else if completedDuration != nil {
                _ = runtime.finishFiniteTask(requestID: current.request.requestID)
                candidate = nil
            }
        }
        if let completedDuration {
            durationEpoch = nil
            pending = nil
            finishDurationOwner(completedDuration)
        }
        drainPending(); synchronize()
    }
    private func drainPending() {
        guard sceneActive, submitTask == nil, let epoch = pending, epoch.demand.goal != nil else { return }
        guard ownerReady(epoch.demand) else {
            logOwnerBlocked(epoch.demand)
            return
        }
        lastBlockedKey = nil
        if let current = candidate {
            // A pending prepare cannot replace the healthy previous owner.
            guard service.movementAuthority.snapshot.lease != current.request.lease else { return }
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        guard let goal = epoch.demand.goal else { return }
        let text = presentation(epoch.demand.kind, epoch.progress ?? .zero)
        guard let request = ContinuedProcessingRequest(movementID: epoch.demand.movementID,
            lease: epoch.demand.lease, kind: epoch.demand.kind, goal: goal,
            title: text.title, subtitle: text.subtitle) else {
            pending = nil; noticeKey = "background.rejected"; return
        }
        pending = nil; candidate = Candidate(request: request, epoch: epoch)
        submissionID = request.requestID
        let id = request.requestID
        submitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.sceneActive, self.candidate?.request.requestID == id,
                  self.ownerReady(epoch.demand) else {
                diagnose("background.submitAborted", category: .background, level: .notice, [
                    "kind": .text(epoch.demand.kind.rawValue),
                    "scene": .flag(self.sceneActive),
                    "candidate": .flag(self.candidate?.request.requestID == id)
                ])
                self.submissionReturned(id, accepted: false); return
            }
            let accepted = await self.runtime.begin(request, isForeground: true)
            self.submissionReturned(id, accepted: accepted)
        }
    }
    private func submissionReturned(_ id: UUID, accepted: Bool) {
        guard submissionID == id else { return }
        submissionID = nil; submitTask = nil
        if candidate?.request.requestID == id {
            if accepted { forwardProgress() }
            else {
                if let current = candidate, current.boundGrant != nil {
                    pauseForRuntimeLoss(current, notice: failureNotice(runtime.error))
                }
                candidate = nil; noticeKey = failureNotice(runtime.error)
            }
        }
        drainPending(); synchronize()
    }
    private func launched(_ grant: ContinuedProcessingGrant) {
        guard var current = candidate, current.request.requestID == grant.requestID,
              current.epoch.matches(grant.movementID, grant.lease), ownerReady(current.epoch.demand),
              service.bindMovementContinuation(grant) else {
            runtime.cancel(requestID: grant.requestID)
            noticeKey = "background.unavailable"; synchronize(); return
        }
        current.boundGrant = grant; candidate = current
        forwardProgress()
        if !grant.isValid { pauseForRuntimeLoss(current, notice: "background.expired") }
        synchronize()
    }
    private func lostRuntime(_ id: UUID, _ reason: ContinuedProcessingRuntimeLoss) {
        guard let current = candidate, current.request.requestID == id else { return }
        guard reason != .cancelled, reason != .superseded else { synchronize(); return }
        let key = reason == .expired ? "background.expired" :
            (reason == .submissionRejected ? failureNotice(runtime.error) : "background.unavailable")
        if current.boundGrant != nil || !sceneActive { pauseForRuntimeLoss(current, notice: key) }
        else { noticeKey = key } // Rejection without a bound grant preserves foreground work.
        synchronize()
    }
    private func pauseForRuntimeLoss(_ current: Candidate, notice: String) {
        diagnose("background.pause", category: .background, level: .notice, [
            "notice": .text(notice),
            "bound": .flag(current.boundGrant != nil),
            "state": .text(String(describing: runtime.state))
        ])
        noticeKey = notice; handlingRuntimeLoss = true
        service.markSimulationPositionUnverified()
        if route.intent?.id == current.request.movementID, route.intent?.lease == current.request.lease {
            route.continuationDidBecomeUnavailable()
        } else if joystick.intent?.id == current.request.movementID, joystick.intent?.lease == current.request.lease {
            joystick.continuationDidBecomeUnavailable()
        } else if positionHold?.intent?.id == current.request.movementID,
                  positionHold?.intent?.lease == current.request.lease {
            positionHold?.continuationDidBecomeUnavailable()
        }
        handlingRuntimeLoss = false; noticeKey = notice
    }
    private func finishDurationOwner(_ demand: MovementContinuationDemand) {
        handlingRuntimeLoss = true
        service.markSimulationPositionUnverified()
        if route.intent?.id == demand.movementID, route.intent?.lease == demand.lease {
            route.continuationDidBecomeUnavailable()
        } else if joystick.intent?.id == demand.movementID, joystick.intent?.lease == demand.lease {
            joystick.continuationDidBecomeUnavailable()
        }
        // The fixed-position controller ends its own stream after publishing
        // this final ACK; do not turn its normal completion into an expiry.
        handlingRuntimeLoss = false
        noticeKey = "background.durationCompleted"
    }
    private func retireCurrent(reason: MovementContinuationRetirement, line: Int = #line) {
        guard let current = candidate else { return }
        let owner = service.movementAuthority.snapshot
        let health: String
        switch owner.health {
        case .confirmedHealthy: health = "healthy"
        case .interrupted: health = "interrupted"
        case .unknown: health = "unknown"
        case nil: health = "none"
        }
        diagnose("background.retire", category: .background, level: .notice, [
            "reason": .text(reason.diagnosticsLabel),
            "line": .count(line),
            "kind": .text(String(describing: current.request.kind)),
            "owner_health": .text(health),
            "owner_run": .text(owner.runState.map { String(describing: $0) } ?? "none"),
            "owner_match": .flag(owner.lease == current.request.lease),
            "conn": .text(String(describing: service.movementConnection)),
            "cold_clear": .flag(service.coldClearPending)
        ])
        candidate = nil // Retire identity before potentially reentrant driver callbacks.
        _ = service.retireMovementContinuation(requestID: current.request.requestID,
            lease: current.request.lease, reason: reason)
        if submissionID == current.request.requestID { submitTask?.cancel() }
        _ = runtime.cancel(requestID: current.request.requestID)
    }
    private func movementBoundary(_ lease: MovementTaskLease?) {
        if lease == nil { pending = nil; noticeKey = nil }
        if let epoch = durationEpoch, lease != epoch.demand.lease { durationEpoch = nil }
        if let current = candidate, lease != current.request.lease { retireCurrent(reason: .ownerPausedOrEnded) }
        synchronize()
    }
    private func ownerReady(_ demand: MovementContinuationDemand) -> Bool {
        let owner = service.movementAuthority.snapshot
        if owner.lease == demand.lease, owner.runState == .running,
           service.isRecoveringConnection || route.isRecoveringConnection || joystick.isRecoveringConnection || positionHold?.isRecoveringConnection == true {
            return true
        }
        guard owner.lease == demand.lease, owner.health == .confirmedHealthy,
              owner.runState == .running, service.movementConnection != .unavailable,
              !service.coldClearPending else { return false }
        switch demand.kind {
        case .finiteRoute, .roundTrip:
            return route.phase == .running && route.intent?.id == demand.movementID && route.intent?.lease == demand.lease
        case .wander:
            // Service emits its first accepted ACK before the controller's
            // async return; the installed healthy owner is already real.
            return [.preparing, .moving].contains(joystick.phase) && joystick.wanderEnabled &&
                joystick.intent?.id == demand.movementID && joystick.intent?.lease == demand.lease
        case .fixedPosition:
            return positionHold?.phase == .running && positionHold?.intent?.id == demand.movementID &&
                positionHold?.intent?.lease == demand.lease
        }
    }
    /// Diagnostics only: records the owner snapshot and the active movement
    /// that hold a demand back, once per movement and state, so a stuck
    /// request leaves one record instead of one per drain.
    private func logOwnerBlocked(_ demand: MovementContinuationDemand) {
        let owner = service.movementAuthority.snapshot
        let active = ActiveMovement(route: route, joystick: joystick, positionHold: positionHold)?.diagnosticsLabel ?? "none"
        let state = "\(owner.lease == demand.lease)/\(owner.health)/\(owner.runState)/\(active)"
        let key = "\(demand.movementID.uuidString)/\(state)"
        guard key != lastBlockedKey else { return }
        lastBlockedKey = key
        diagnose("background.blocked", category: .background, level: .notice, [
            "kind": .text(demand.kind.rawValue),
            "leaseMatches": .flag(owner.lease == demand.lease),
            "health": .text(String(describing: owner.health)),
            "runState": .text(String(describing: owner.runState)),
            "connection": .text(String(describing: service.movementConnection)),
            "coldClearPending": .flag(service.coldClearPending),
            "active": .text(active),
            "movement": .text(demand.movementID.uuidString)
        ])
    }
    private func forwardProgress() {
        guard let current = candidate, let progress = current.epoch.progress else { return }
        diagnose("background.progress", category: .background, [
            "writes": .count(Int(progress.acknowledgedWrites)),
            "distance_m": .number(progress.cumulativeAcknowledgedDistanceMeters, digits: 1),
            "duration_s": .number(progress.cumulativeAcknowledgedDurationSeconds, digits: 1)
        ])
        let text = presentation(current.request.kind, progress)
        _ = runtime.update(requestID: current.request.requestID, progress: progress,
            title: text.title, subtitle: text.subtitle)
    }
    private func queueCleanup() {
        guard !cleanupQueued else { return }
        cleanupQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.cleanupQueued = false
            if let current = self.candidate {
                let owner = self.service.movementAuthority.snapshot
                if owner.lease != current.request.lease || owner.health != .confirmedHealthy || owner.runState != .running {
                    self.retireCurrent(reason: .ownerPausedOrEnded)
                }
            }
            if let epoch = self.pending {
                let id = epoch.demand.movementID
                if self.route.intent?.id != id && self.joystick.intent?.id != id &&
                    self.positionHold?.intent?.id != id { self.pending = nil }
            }
            // The one coalesced relay also publishes a suspended submission's
            // state and buffers real ACK progress before its launch/return.
            // It never creates consent, grants admission, or submits work.
            self.forwardProgress()
            // A request made before its owner's lease was installed waits here;
            // the owner confirming is a domain change, not only an ACK.
            self.drainPending()
            self.synchronize()
        }
    }
    private func observeDomainMutation() {
        if !handlingRuntimeLoss, let current = candidate,
           current.boundGrant?.isValid == false,
           service.movementContinuationIsBound(requestID: current.request.requestID,
               lease: current.request.lease),
           service.movementAuthority.snapshot.health == .confirmedHealthy {
            pending = nil
            pauseForRuntimeLoss(current, notice: "background.expired")
        }
        queueCleanup()
    }
    private func rejectInvalidProgress() {
        pending = nil
        if let current = candidate { pauseForRuntimeLoss(current, notice: "background.rejected") }
        retireCurrent(reason: .ownerPausedOrEnded)
        noticeKey = "background.rejected"; synchronize()
    }
    private func failureNotice(_ failure: ContinuedProcessingFailure?) -> String {
        switch failure {
        case .registrationLimitReached: "background.registrationLimit"
        case .unsupportedSystem: "background.unsupported"
        default: "background.rejected"
        }
    }
    private func synchronize() {
        receipts = runtime.receipts
    }
}

private func diagnose(_ name: String, category: DiagnosticsCategory, level: DiagnosticsLevel = .debug,
                      _ fields: [String: DiagnosticsField] = [:]) {
    Diagnostics.shared.record(name, category: category, level: level, fields)
}
