import Combine
import Foundation

/// Coordinates foreground reachability checks and the data-only recovery
/// projection and serialized repair of an already-running movement owner.
@MainActor
public final class ConnectionRecoveryController: ObservableObject {
    @Published public private(set) var connectionState: VPNCheckState = .unknown
    @Published public private(set) var isChecking = false
    @Published public private(set) var checkpointRevision: UInt64 = 0

    private let service: ServiceController
    private let route: RouteExecutionController
    private let joystick: JoystickMovementController
    private let positionHold: PositionHoldController?
    /// Route first, then the hold, then the joystick: the order a recovery's execution ID is matched in.
    private var movementOwners: [any MovementOwner] { [route] + (positionHold.map { [$0] } ?? []) + [joystick] }
    @Published public private(set) var automaticRepairInProgress = false
    /// True while the repair was started automatically (not by the Retry button).
    private var automaticRepairIsSilent = false
    /// An automatic repair is running: the status pill shows connecting, but no
    /// banner or toast is shown until it fails.
    public var isSilentRepairInProgress: Bool { automaticRepairInProgress && automaticRepairIsSilent }
    private var automaticRepairTask: Task<Void, Never>?
    /// The last automatic (not Retry) repair: within one task lease at most
    /// one starts per `automaticRepairSpacing` (ADR 0001).
    private var lastAutomaticRepair: (lease: MovementTaskLease, startedAt: Duration)?
    static let automaticRepairSpacing: Duration = .seconds(60)
    private var failedAutomaticRepair: MovementConnectionRecovery?
    public var canRetryAutomaticRepair: Bool {
        failedAutomaticRepair.map { service.movementAuthority.snapshot.lease == $0.lease } == true
    }
    private let probe: any TunnelProbing
    private let clock: any RouteClock
    private var retainedSnapshot: SessionRecoverySnapshot?
    private var coldSummaryDiscarded = false
    private var discardedColdUncertainty: SessionMovementUncertainty?
    private var sceneActive = false
    private var generation: UInt64 = 0
    private var checkTask: Task<Void, Never>?
    private static let recheckSpacing: Duration = .seconds(5)
    private var foregroundCheckPending = false
    private var lastProbeFinishedAt: Duration?
    private var lastObservedPhase: ServicePhase
    private var recoveredNotice = false
    private var probeStartedFromFailure = false
    private var checkNoticeVisible = false
    private var revisionQueued = false
    private var subscriptions: [AnyCancellable] = []

    public init(
        service: ServiceController,
        route: RouteExecutionController,
        joystick: JoystickMovementController,
        probe: any TunnelProbing,
        positionHold: PositionHoldController? = nil,
        clock: any RouteClock = ContinuousRouteClock(),
        retainedColdSnapshot: SessionRecoverySnapshot? = nil
    ) {
        self.service = service
        self.route = route
        self.joystick = joystick
        self.positionHold = positionHold
        self.probe = probe
        self.clock = clock
        self.retainedSnapshot = retainedColdSnapshot
        self.lastObservedPhase = service.phase

        subscriptions = [
            service.$phase.sink { [weak self] phase in
                self?.receiveServicePhase(phase)
            },
            service.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            route.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            joystick.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            service.joystickEvents.sink { [weak self] event in
                guard case .movementBoundary(nil) = event else { return }
                self?.invalidateProbeForSafety()
            }
        ]

        service.connectionRecoveryRequested = { [weak self] recovery in
            self?.beginAutomaticRepair(recovery) ?? false
        }

        if let retainedColdSnapshot {
            _ = service.restoreColdRecovery(position: retainedColdSnapshot.position)
            if retainedColdSnapshot.activeMovement != nil || retainedColdSnapshot.uncertainty != nil {
                service.markColdClearPending()
                _ = service.beginColdClear()
            }
        }
    }

    deinit {
        checkTask?.cancel()
        automaticRepairTask?.cancel()
    }

    public var requiresColdConfirmation: Bool { service.coldClearPending }

    public var unverifiedMovement: SessionActiveRecovery? {
        guard retainedSummaryAvailable else { return nil }
        return retainedSnapshot?.activeMovement
    }

    public var unverifiedUncertainty: SessionMovementUncertainty? {
        if service.clearState == .confirmed { return nil }
        if retainedSummaryAvailable, let uncertainty = retainedSnapshot?.uncertainty { return uncertainty }
        if let discardedColdUncertainty { return discardedColdUncertainty }
        guard let uncertainty = service.recoveryUncertainty else { return nil }
        return normalized(uncertainty)
    }

    public var noticeKey: String? {
        if service.coldClearPending { return "recovery.coldClearPending" }
        if isSilentRepairInProgress { return nil }
        // No "checking connection" toast: a re-check is silent until it fails or recovers.
        if recoveredNotice { return "recovery.connectionRecovered" }
        switch connectionState {
        case .unavailable, .timedOut: return "recovery.connectionLost"
        case .unknown, .checking, .reachable: return nil
        }
    }

    public var canCheck: Bool {
        sceneActive && !isChecking && checkTask == nil && isManualProbeEligible
    }

    public func sceneDidBecomeActive() {
        guard !sceneActive else { return }
        sceneActive = true
        route.sceneDidBecomeActive()
        joystick.sceneDidBecomeActive()
        // A foreground return is an explicit freshness boundary. It bypasses
        // the ordinary five-second healthy monitor interval, while still
        // requiring an actually ready service or a known connection fence.
        evaluateServiceState(immediate: true)
    }

    /// Wi-Fi, utun or interface changes are a freshness boundary like a
    /// foreground return: one immediate check, no polling afterwards.
    public func networkPathDidChange() {
        guard sceneActive else { return }
        positionHold?.heartbeatNow()
        evaluateServiceState(immediate: true)
    }

    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        cancelAutomaticRepairTask()
        sceneActive = false
        foregroundCheckPending = false
        generation &+= 1
        checkTask?.cancel()
        isChecking = false
        connectionState = .unknown
        recoveredNotice = false
        checkNoticeVisible = false
        if checkTask == nil {
            route.recoveryProbeDidFinish()
            joystick.recoveryProbeDidFinish()
        }
        route.releaseForInactiveScene(continuingLease: continuingLease)
        joystick.releaseForInactiveScene(continuingLease: continuingLease)
    }

    /// Retain foreground freshness requests until native work and cancelled
    /// probes have drained. An active probe already satisfies the request.
    public func requestForegroundCheck() {
        guard sceneActive else { return }
        if checkTask != nil && isChecking { return }
        foregroundCheckPending = true
        evaluateServiceState()
    }

    /// A manual check joins an in-flight check; it never starts a second probe.
    public func checkConnection() {
        if canRetryAutomaticRepair, let failedAutomaticRepair, canCheck {
            // An explicit Retry is not counted and restarts the spacing.
            lastAutomaticRepair = nil
            if service.requestConnectionRecovery(failure: failedAutomaticRepair.failure, explicitlyRequested: true) { return }
        }
        guard sceneActive, isManualProbeEligible else { return }
        guard checkTask == nil else { return }
        beginProbe(manual: true, showCheckingNotice: true)
    }

    /// This forgets the visible old-task summary. The service cold hold remains
    /// until an actual clear acknowledgement releases it.
    public func discardUnverifiedMovement() {
                retainedSnapshot = nil
        coldSummaryDiscarded = true
        if service.coldClearPending {
            discardedColdUncertainty = SessionMovementUncertainty(source: .unverifiedPreviousMovement)
        }
        queueCheckpointRevision()
    }

    public func snapshot(mode: SessionMapMode) -> SessionRecoverySnapshot {
        reconcileColdClear()
        let position = service.positionMarker.map {
            SessionDisplayPosition(coordinate: $0.coordinate, source: $0.source)
        } ?? retainedSnapshot?.position
        let runtime = activeMovement()
        let clearPending = service.clearState != .confirmed &&
            (service.clearState == .pending || service.statusKey == "service.stoppedGPSPending")
        let active = clearPending ? nil : (runtime ?? (coldSummaryDiscarded ? nil : retainedSnapshot?.activeMovement))
        let uncertainty = normalized(service.recoveryUncertainty) ??
            (coldSummaryDiscarded ? discardedColdUncertainty : retainedSnapshot?.uncertainty)
        return SessionRecoverySnapshot(
            mode: mode,
            draft: route.draft,
            roundTripEnabled: route.roundTripEnabled,
            joystickSpeed: joystick.speed,
            position: position,
            activeMovement: active,
            uncertainty: uncertainty
        )
    }

    /// Manual checks are allowed while stopped so an initial or cold session
    /// can explicitly establish connectivity. They never create movement.
    private var isManualProbeEligible: Bool {
        guard !service.nativeBusy else { return false }
        if service.phase == .ready { return true }
        return service.phase == .stopped || service.phase == .repairRequired
    }

    /// Automatic checks require actual service readiness, or a connection that
    /// is not yet confirmed (app launch: `.connecting`) or known unavailable.
    /// A cold hold alone is display state, not
    /// evidence that a probe should run.
    private var isAutomaticProbeEligible: Bool {
        guard !service.nativeBusy else { return false }
        if service.phase == .ready { return true }
        guard service.phase == .stopped || service.phase == .repairRequired else { return false }
        return service.movementConnection != .available
    }

    private var retainedSummaryAvailable: Bool {
        !coldSummaryDiscarded && service.clearState != .confirmed
    }

    private func evaluateServiceState(immediate: Bool = false) {
        guard !automaticRepairInProgress else { return }
        let phase = service.phase
        if lastObservedPhase == .ready, phase != .ready {
            generation &+= 1
            checkTask?.cancel()
            isChecking = false
            connectionState = .unknown
            checkNoticeVisible = false
        }
        lastObservedPhase = phase
        guard sceneActive else { return }
        if foregroundCheckPending, isManualProbeEligible {
            // A cancelled old probe still owns checkTask until it returns.
            // Keep the request latched and consume it only when we can start.
            guard checkTask == nil else { return }
            beginProbe(manual: true)
            return
        }
        guard isAutomaticProbeEligible else {
            return
        }
        scheduleProbeIfDue(immediate: immediate)
    }

    /// Probes are event-driven: a scene activation or path change asks for an
    /// immediate check; an unknown or lost connection is re-checked on later
    /// state changes at most every five seconds; a reachable one is not
    /// re-checked at all. There is no periodic timer; movement ACKs prove
    /// liveness while a task runs.
    private func scheduleProbeIfDue(immediate: Bool = false) {
        guard sceneActive, isAutomaticProbeEligible, checkTask == nil else { return }
        if !immediate, let lastProbeFinishedAt {
            guard connectionState != .reachable,
                  clock.now - lastProbeFinishedAt >= Self.recheckSpacing else { return }
        }
        beginProbe(showCheckingNotice: immediate)
    }

    private func beginProbe(manual: Bool = false, showCheckingNotice: Bool = false) {
        guard !automaticRepairInProgress else { return }
        let eligible = manual ? isManualProbeEligible : isAutomaticProbeEligible
        guard sceneActive, eligible, checkTask == nil else { return }
        foregroundCheckPending = false
        generation &+= 1
        let token = generation
        let probe = probe
        probeStartedFromFailure = connectionState == .unavailable || connectionState == .timedOut
        recoveredNotice = false
        // Re-checking a connection that last succeeded is silent. The first probe
        // after launch (`.connecting`) shows no toast either; only re-checking a
        // known failure shows the checking notice.
        checkNoticeVisible = showCheckingNotice && service.movementConnection == .unavailable
        isChecking = true
        if connectionState == .unknown { connectionState = .checking }
        let probeStartedAt = clock.now
        diagnose("tunnel.probe.start", category: .tunnel, level: .notice, [
            "manual": .flag(manual),
            "phase": .text(service.phase.rawValue),
            "busy": .flag(service.nativeBusy)
        ])
        route.recoveryProbeDidStart()
        joystick.recoveryProbeDidStart()
        checkTask = Task { [weak self] in
            let result: Result<Void, TunnelProbeFailure>
            do {
                try await probe.check()
                result = .success(())
            } catch let failure as TunnelProbeFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.unavailable)
            }
            guard let self else { return }
            guard self.generation == token, self.sceneActive else {
                // Keep the in-flight reference until this task has actually
                // observed cancellation. This is the max-one probe boundary.
                self.checkTask = nil
                self.checkNoticeVisible = false
                self.route.recoveryProbeDidFinish()
                self.joystick.recoveryProbeDidFinish()
                if self.sceneActive { self.evaluateServiceState(immediate: true) }
                return
            }
            self.checkTask = nil
            self.isChecking = false
            self.checkNoticeVisible = false
            self.route.recoveryProbeDidFinish()
            self.joystick.recoveryProbeDidFinish()
            self.lastProbeFinishedAt = self.clock.now
            let elapsed = self.clock.now - probeStartedAt
            let elapsedMs = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15
            switch result {
            case .success:
                diagnose("tunnel.probe.end", category: .tunnel, level: .notice, [
                    "result": .text("reachable"),
                    "ms": .milliseconds(elapsedMs),
                    "recovered": .flag(self.probeStartedFromFailure)
                ])
                if !self.canRetryAutomaticRepair {
                    self.finishConnectionRecovery(recovered: self.probeStartedFromFailure)
                }
            case .failure(let failure):
                diagnose("tunnel.probe.end", category: .tunnel, level: .error, [
                    "result": .text(failure == .timedOut ? "timedOut" : "unavailable"),
                    "ms": .milliseconds(elapsedMs),
                    "phase": .text(self.service.phase.rawValue)
                ])
                self.connectionState = failure == .timedOut ? .timedOut : .unavailable
                let snapshot = self.service.movementAuthority.snapshot
                if snapshot.lease != nil, snapshot.runState == .running {
                    // A running task is left alone: its next write proves or
                    // disproves the connection, and the device keeper owns
                    // the one automatic reconnect.
                    self.positionHold?.heartbeatNow()
                } else {
                    self.service.setMovementConnectionAvailable(false)
                    self.route.connectionDidBecomeUnavailable()
                    self.joystick.connectionDidBecomeUnavailable()
                }

            }
            self.scheduleProbeIfDue()
        }
    }

    private func beginAutomaticRepair(_ recovery: MovementConnectionRecovery) -> Bool {
        guard !automaticRepairInProgress else { return true }
        if !recovery.explicitlyRequested {
            // A failed attempt waits for Retry; a recent one shows the loss instead of repairing again.
            guard failedAutomaticRepair?.lease != recovery.lease else { return false }
            if let last = lastAutomaticRepair, last.lease == recovery.lease,
               clock.now - last.startedAt < Self.automaticRepairSpacing { return false }
        }
        let suspended: Bool
        if !recovery.resumesTask {
            // Explicit Retry repairs the connection of a user-paused task;
            // its scheduler stays paused until the separate Resume action.
            suspended = service.movementAuthority.snapshot.runState == .paused
        } else if let owner = movementOwners.first(where: { $0.movementID == recovery.executionID }) {
            suspended = owner.suspendForConnectionRecovery()
        } else { return false }
        guard suspended else { return false }
        if !recovery.explicitlyRequested { lastAutomaticRepair = (recovery.lease, clock.now) }
        automaticRepairIsSilent = !recovery.explicitlyRequested
        automaticRepairInProgress = true
        generation &+= 1
        checkTask?.cancel()
        isChecking = false
        connectionState = recovery.failure == .operationTimedOut ? .timedOut : .unavailable
        checkNoticeVisible = false
        route.recoveryProbeDidFinish(); joystick.recoveryProbeDidFinish()
        // An automatic attempt runs silently; a Retry in flight replaces the
        // earlier failure. Retry stays unavailable until this attempt settles,
        // and a failed attempt waits for an explicit Retry.
        failedAutomaticRepair = nil
        automaticRepairTask = Task { [weak self] in
            guard let self else { return }
            // The callback is synchronous, before the native failure unwinds.
            // Queue repair after the service has closed ordinary admission.
            await Task.yield()
            let success = await self.service.repairConnection(recovery)
            if success {
                for owner in self.movementOwners { owner.finishConnectionRecovery(succeeded: true) }
            } else if self.service.movementConnection == .unavailable {
                // Preserve the suspended logical task for the explicit retry
                // action. Periodic probes never reset this attempt budget.
                self.failedAutomaticRepair = recovery
            }
            self.automaticRepairInProgress = false
            self.automaticRepairTask = nil
            self.lastProbeFinishedAt = self.clock.now
            if success || self.service.movementConnection != .unavailable {
                self.failedAutomaticRepair = nil
                // An automatic repair recovers silently: no "recovered" notice.
                self.finishConnectionRecovery(recovered: recovery.explicitlyRequested)
            }
            self.evaluateServiceState()
        }
        return true
    }

    private func receiveServicePhase(_ phase: ServicePhase) {
        guard phase == .stopping || phase == .restoring else { return }
        cancelAutomaticRepairTask()
    }

    private func cancelAutomaticRepairTask() {
        automaticRepairTask?.cancel()
    }

    private func finishConnectionRecovery(recovered: Bool) {
        connectionState = .reachable
        recoveredNotice = recovered
        service.setMovementConnectionAvailable(true)
        route.connectionDidBecomeAvailable()
        joystick.connectionDidBecomeAvailable()
    }

    /// Stop/reset emits this synchronously before any adapter clear work. It
    /// invalidates an in-flight probe generation before a late positive can
    /// reopen movement admission.
    private func invalidateProbeForSafety() {
        foregroundCheckPending = false
        cancelAutomaticRepairTask()
        generation &+= 1
        checkTask?.cancel()
        isChecking = false
        connectionState = .unknown
        checkNoticeVisible = false
        route.recoveryProbeDidFinish()
        joystick.recoveryProbeDidFinish()
    }

    private func observeDomainMutation() {
                queueCheckpointRevision()
        let token = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.generation == token else { return }
            self.evaluateServiceState()
        }
    }

    private func queueCheckpointRevision() {
                guard !revisionQueued else { return }
        revisionQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.revisionQueued = false
            if self.checkpointRevision < UInt64.max { self.checkpointRevision += 1 }
        }
    }

    private func reconcileColdClear() {
        guard service.clearState == .confirmed else { return }
        retainedSnapshot = nil
        coldSummaryDiscarded = true
        discardedColdUncertainty = nil
    }

    private func normalized(_ uncertainty: SessionMovementUncertainty?) -> SessionMovementUncertainty? {
        guard let uncertainty else { return nil }
        if uncertainty.source == .joystick, joystick.wanderEnabled {
            return SessionMovementUncertainty(source: .wander, requestedPlace: uncertainty.requestedPlace)
        }
        return uncertainty
    }

    private func activeMovement() -> SessionActiveRecovery? {
        // Manual input has no safe replay payload. Preserve only an installed
        // owner; a preparing gesture has no native claim to report.
        if joystick.recoveryHasAcknowledgedLease,
           joystick.intent != nil, !joystick.wanderEnabled,
           [.moving, .settling, .paused].contains(joystick.phase) {
            return .manual
        }

        let authority = service.movementAuthority.snapshot
        guard let lease = authority.lease,
              authority.health == .confirmedHealthy,
              authority.runState != nil else { return nil }

        if let intent = route.intent, intent.lease == lease,
           let progress = route.progress,
           [.running, .paused].contains(route.phase) {
            return .route(SessionRouteRecovery(
                draft: intent.draft,
                route: intent.route,
                progress: progress,
                roundTripEnabled: route.roundTripEnabled,
                usesPositionAxis: route.usesPositionAxis,
                heading: route.heading,
                state: route.phase == .running ? .running : .paused
            ))
        }

        if let intent = joystick.intent, intent.lease == lease,
           joystick.wanderEnabled,
           let coordinate = joystick.lastAcknowledgedCoordinate,
           [.moving, .paused, .suspended].contains(joystick.phase),
           let target = joystick.wanderTarget {
            return .wander(SessionWanderRecovery(
                target: target,
                speed: joystick.speed,
                history: joystick.recoveryWanderHistory,
                lastAcknowledgedCoordinate: coordinate,
                lastAcknowledgedBearingDegrees: joystick.lastAcknowledgedBearingDegrees,
                state: joystick.phase == .moving ? .running : .paused
            ))
        }

        return nil
    }
}

private func diagnose(_ name: String, category: DiagnosticsCategory, level: DiagnosticsLevel = .debug,
                      _ fields: [String: DiagnosticsField] = [:]) {
    Diagnostics.shared.record(name, category: category, level: level, fields)
}
