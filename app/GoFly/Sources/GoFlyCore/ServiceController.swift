import Combine
import Foundation

public enum MovementConnectionState: Equatable, Sendable {
    /// No real probe/repair result yet.
    case connecting, available, unavailable
}

@MainActor
public final class ServiceController: ObservableObject, RouteCommanding, JoystickCommanding {
    @Published public private(set) var phase: ServicePhase = .stopped
    @Published public private(set) var nativeBusy = false
    @Published public private(set) var hasSimulated = false
    @Published public private(set) var isRecoveringConnection = false
    public var connectionRecoveryRequested: (@MainActor (MovementConnectionRecovery) -> Bool)?
    private var connectionRecovery: MovementConnectionRecovery?
    private var failedConnectionRecovery: MovementConnectionRecovery?
    private var connectionRecoveryGate: PointDispatchGate?
    @Published public private(set) var error: DeviceServiceFailure?
    @Published public private(set) var clearState: ClearState = .unknown
    @Published public private(set) var clearConfirmedAt: Date?
    @Published public private(set) var realLocation: RealLocationObservation?
    @Published public private(set) var pointState: PointMoveState = .idle
    @Published public private(set) var confirmedSimulatedLocation: GeoCoordinate?
    @Published private var simulationDisplayVerified = false
    @Published public private(set) var preparedOperation: PreparedOperationSnapshot?
    /// TCP reachability is an admission signal only. It never claims native
    /// service health or changes the current task lease.
    /// `.connecting` until a real tunnel probe or repair reports a result.
    @Published public private(set) var movementConnection: MovementConnectionState = .connecting
    // While `.connecting`, admission stays open (the result is neither success
    // nor failure yet), so no error is surfaced. Automatic actions that need the
    // tunnel compare against `.available` instead.
    @Published public private(set) var coldClearPending = false
    private var coldClearAttempt = false

    private struct DisplayedPosition {
        let coordinate: GeoCoordinate
        let source: PositionSource
    }
    private struct PointContext: Sendable {
        let intent: PointMoveIntent
        let dispatch: PointDispatchGate
        let wasReady: Bool
        let lease: MovementTaskLease
        let displayEpoch: UUID
        let admissionRevision: UInt64
    }
    private struct PreparationContext: Sendable {
        let id: UUID
        let source: PreparedOperationSource
        let dispatch: PointDispatchGate
        let wasReady: Bool
        let displayEpoch: UUID
    }
    private enum CommandResult: Sendable {
        case success
        case failure(DeviceServiceFailure)
        case point(PointDeliveryOutcome)
    }

    public let movementAuthority: MovementTaskAuthority
    private struct AdapterCommand {
        let work: @MainActor @Sendable (any DeviceService) async -> CommandResult
        let completion: @MainActor (CommandResult) -> Void
    }
    private final class RouteOwner {
        let intent: RouteExecutionIntent
        let stopGeneration: UInt64
        var begun = false
        var ended = false
        var unknown = false
        var unknownFailure: DeviceServiceFailure?
        var interrupted = false
        var pendingCalls = 0
        var lastSequence: UInt64 = 0
        var controlRevision: UInt64 = 0
        var begin: CheckedContinuation<RouteCommandOutcome, Never>?
        var idle: [CheckedContinuation<RouteIdleSettlement, Never>] = []
        var tick: RouteTick?
        init(_ intent: RouteExecutionIntent, stopGeneration: UInt64, begin: CheckedContinuation<RouteCommandOutcome, Never>) {
            self.intent = intent; self.stopGeneration = stopGeneration; self.begin = begin
        }
    }
    private final class RouteTick {
        let gate: PointDispatchGate
        let coordinate: GeoCoordinate
        let sequence: UInt64
        let displayEpoch: UUID
        var timedOut = false
        var controlCancelled = false
        var skipped = false
        var didInvalidateProof = false
        var watchdog: Task<Void, Never>?
        init(gate: PointDispatchGate, coordinate: GeoCoordinate, sequence: UInt64, displayEpoch: UUID) {
            self.gate = gate; self.coordinate = coordinate; self.sequence = sequence
            self.displayEpoch = displayEpoch
        }
    }
    private final class JoystickOwner {
        let intent: JoystickMovementIntent
        let stopGeneration: UInt64
        var prepared = false
        var installed = false
        var neutral = false
        var paused = false
        var ended = false
        var unknownFailure: DeviceServiceFailure?
        var pendingCalls = 0
        var lastSequence: UInt64 = 0
        var tick: JoystickTick?
        var disposition: JoystickReleaseDisposition?
        var idle: [CheckedContinuation<JoystickIdleSettlement, Never>] = []
        var inputRevision = JoystickInputRevision()
        var begin: CheckedContinuation<JoystickPreparationOutcome, Never>?
        init(_ intent: JoystickMovementIntent, stopGeneration: UInt64,
             begin: CheckedContinuation<JoystickPreparationOutcome, Never>) {
            self.intent = intent; self.stopGeneration = stopGeneration; self.begin = begin
        }
    }
    private final class JoystickTick {
        let sequence: UInt64
        let input: JoystickInputRevision
        let displayEpoch: UUID
        var origin: GeoCoordinate?
        var gate: PointDispatchGate?
        var receipt: JoystickStepReceipt?
        var failure: JoystickFailure?
        var inputCancelled = false
        var timedOut = false
        var didInvalidateProof = false
        var watchdog: Task<Void, Never>?
        init(sequence: UInt64, input: JoystickInputRevision, displayEpoch: UUID) {
            self.sequence = sequence; self.input = input
            self.displayEpoch = displayEpoch
        }
    }
    private var joystickUnconfirmed = false
    private var joystickOwners: [UUID: JoystickOwner] = [:]
    private let joystickSubject = PassthroughSubject<JoystickCommandEvent, Never>()
    private let movementAcknowledgementSubject = PassthroughSubject<MovementAcknowledgement, Never>()
    private let teleportAcknowledgementSubject = PassthroughSubject<TeleportAcknowledgement, Never>()
    public private(set) var routeAdmissionRevision: UInt64 = 0
    private let routeSubject = PassthroughSubject<RouteCommandEvent, Never>()
    private var routeOwners: [UUID: RouteOwner] = [:]
    private var routeUnconfirmed = false
    private var routeStopGeneration: UInt64 = 0
    private let service: any DeviceService
    private let operationTimeout: Duration
    private let watchdogSleep: @MainActor @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var outstandingWork = 0
    private var clearScheduled = false
    private var clearAttempted = false
    private var lastDisplayedPosition: DisplayedPosition?
    /// From an acknowledged simulated write until Stop or an acknowledged clear.
    private var deviceMayHoldSimulation = false
    private var simulationDisplayEpoch = UUID()
    private var didRestoreColdRecovery = false
    private var didPerformActualOperation = false
    /// Session activity begins with an admitted explicit operation. Restoring
    /// display history, automatic cold clear and warmup do not start a task.
    public var hasAdmittedExplicitOperation: Bool { didPerformActualOperation }
    private var currentPoint: PointContext?
    private var currentPreparation: PreparationContext?
    private var adapterQueue: [AdapterCommand] = []
    private var pumping = false
    private var watchdog: Task<Void, Never>?
    private var completedTickCount: UInt64 = 0
    /// The lifecycle token of a forced Reset; its clear failure never leaves an error behind.
    private var forcedResetToken: UInt64?
    /// Start rebuilds the connection first when the last session ended badly.
    private var startRebuildsConnection = false

    public init(
        service: any DeviceService, operationTimeout: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() },
        movementAuthority: MovementTaskAuthority = MovementTaskAuthority(),
        watchdogSleep: @escaping @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.movementAuthority = movementAuthority
        self.operationTimeout = operationTimeout
        self.watchdogSleep = watchdogSleep
        self.now = now
    }
    public var statusKey: String {
        if phase == .stopped, clearAttempted, clearState == .unknown {
            return "service.stoppedGPSPending"
        }
        if phase == .ready, hasSimulated { return "service.running" }
        return "service.\(phase.rawValue)"
    }
    public var gpsStatusKey: String {
        switch clearState {
        case .unknown: return "gps.unknown"
        case .pending: return "gps.clearing"
        case .confirmed:
            guard let realLocation, let clearConfirmedAt,
                  realLocation.observedAt >= clearConfirmedAt else { return "gps.clearedWaiting" }
            return "gps.observed"
        }
    }
    public var canStart: Bool { !nativeBusy && movementAdmissionAllowed && (phase == .stopped || (phase == .ready && hasSimulated && movementAuthority.snapshot.lease == nil)) }
    public var canStop: Bool {
        !clearScheduled && (phase == .ready || phase == .preparing || phase == .repairRequired || isRecoveringConnection)
    }
    public var canRestoreGPS: Bool { !nativeBusy && (phase == .stopped || (phase == .ready && movementAuthority.snapshot.lease == nil)) }
    /// Reset is the manual way out after Stop failed or the service is stuck.
    public var canForceReset: Bool {
        guard forcedResetToken == nil else { return false }
        if phase == .repairRequired { return true }
        return phase == .stopped && !nativeBusy && clearAttempted && clearState == .unknown
    }
    public var canTeleport: Bool {
        !nativeBusy && movementAdmissionAllowed && !pointUnconfirmed && !routeUnconfirmed && !joystickUnconfirmed && (phase == .stopped || phase == .ready)
    }
    private var movementAdmissionAllowed: Bool { !movementAuthority.isAdmissionBlocked }
    private var pointUnconfirmed: Bool {
        if case .unconfirmed = pointState { return true }
        return false
    }



    /// Called by the coordinator after a real tunnel probe. The fence is
    /// linearized before available gates are invalidated so a queued native
    /// head cannot claim between the two operations.
    public func setMovementConnectionAvailable(_ available: Bool) {
        let wasAvailable = movementConnection != .unavailable
        let newState: MovementConnectionState = available ? .available : .unavailable
        guard wasAvailable != available else {
            if movementConnection != newState { movementConnection = newState }
            return
        }
        diagnose("tunnel.admission", category: .tunnel, level: .notice,
                 ["available": .flag(available), "phase": .text(phase.rawValue)])
        movementAuthority.setAdmissionFence(connectionBlocked: !available, coldRecoveryHeld: false)
        routeAdmissionRevision &+= 1
        if !available {
            invalidateAvailableMovementGates()
            markSimulationPositionUnverified()
        }
        // Published observers see the already-closed authority fence. This
        // avoids an admission race from an objectWillChange callback.
        movementConnection = newState
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    /// Updates the scene fence used by native claim admission. Scene changes
    /// do not revoke a live grant or pause an owner; the facade performs that
    /// lifecycle action after closing this fence.
    public func setMovementSceneActive(_ active: Bool) {
        movementAuthority.setSceneActive(active)
        if !active, !hasBackgroundSimulationRuntime { markSimulationPositionUnverified() }
        routeAdmissionRevision &+= 1
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    private var hasBackgroundSimulationRuntime: Bool {
        guard let lease = movementAuthority.snapshot.lease else { return false }
        return movementAuthority.permitsDispatch(for: lease)
    }

    /// Retains the last ACK coordinate as display history. A foreground return
    /// or a successful TCP probe cannot verify the native location session.
    func markSimulationPositionUnverified() {
        // Also advance while already waiting: an in-flight first ACK must not
        // verify a session across an intervening loss and recovery.
        simulationDisplayEpoch = UUID()
        guard simulationDisplayVerified else { return }
        simulationDisplayVerified = false
    }

    /// Binds a concrete framework grant to the currently healthy native owner.
    /// The owner check is intentionally based on ServiceController state, so a
    /// caller cannot manufacture health by presenting a grant alone.
    @discardableResult
    public func bindMovementContinuation(_ grant: ContinuedProcessingGrant) -> Bool {
        guard grant.isValid, !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              let owner = movementOwner(movementID: grant.movementID, lease: grant.lease),
              owner.isHealthyRunning else {
            diagnose("background.bindRejected", category: .background, level: .notice, [
                "valid": .flag(grant.isValid),
                "clear": .flag(clearScheduled),
                "unconfirmed": .flag(routeUnconfirmed || joystickUnconfirmed)
            ])
            return false
        }
        let bound = movementAuthority.bind(grant)
        diagnose("background.bound", category: .background, level: .notice, ["bound": .flag(bound)])
        return bound
    }

    public func hasMovementContinuation(movementID: UUID, lease: MovementTaskLease,
                                        requestID: UUID) -> Bool {
        guard let owner = movementOwner(movementID: movementID, lease: lease), owner.isHealthyRunning else { return false }
        return movementAuthority.hasValidBinding(movementID: movementID, lease: lease, requestID: requestID)
    }

    /// Reports the exact runtime binding without treating a closed grant as
    /// dispatch-valid. Facades use this distinction to tell a trusted atomic
    /// resume apart from a binding that has already been retired.
    func movementContinuationIsBound(requestID: UUID, lease: MovementTaskLease) -> Bool {
        movementAuthority.bindingMatches(requestID: requestID, lease: lease)
    }

    private func pauseExpiredContinuation(movementID: UUID, lease: MovementTaskLease,
                                          result: CommandResult) -> Bool {
        // Only an explicitly unsent runtime denial is safe to pause. Claimed,
        // malformed, timed-out and uncertain native results keep their existing
        // interruption/recovery paths.
        switch result {
        case .point(.notSent(.operationCancelled)), .point(.notSent(.serviceUnavailable)),
             .failure(.operationCancelled), .failure(.serviceUnavailable): break
        default: return false
        }
        guard !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              movementOwner(movementID: movementID, lease: lease)?.isHealthyRunning == true,
              movementAuthority.pauseForClosedBinding(movementID: movementID, lease: lease) else { return false }
        markSimulationPositionUnverified()
        diagnose("background.bindingClosed", category: .background, level: .notice,
                 ["movement": .text(movementID.uuidString), "lease": .text(lease.id.uuidString)])
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
        return true
    }

    @discardableResult
    public func retireMovementContinuation(requestID: UUID, lease: MovementTaskLease,
                                           reason: MovementContinuationRetirement) -> Bool {
        guard movementAuthority.bindingMatches(requestID: requestID, lease: lease) else { return false }
        switch reason {
        case .ownerPausedOrEnded:
            if let owner = movementOwner(lease: lease) {
                guard !owner.isHealthyRunning else { return false }
            } else {
                let snapshot = movementAuthority.snapshot
                guard snapshot.lease != lease || snapshot.runState != .running ||
                      snapshot.health != .confirmedHealthy else { return false }
            }
        case .foregroundGoalChange:
            guard movementAuthority.isSceneActive,
                  let owner = movementOwner(lease: lease), owner.isHealthyRunning,
                  movementAuthority.hasValidBinding(movementID: owner.movementID,
                      lease: lease, requestID: requestID) else { return false }
        case .foregroundManualAfterAutoOff:
            guard movementAuthority.isSceneActive,
                  let owner = joystickOwners.values.first(where: {
                      $0.intent.lease == lease && $0.installed && !$0.ended && !$0.neutral &&
                      !$0.paused && $0.unknownFailure == nil
                  }),
                  let view = movementOwner(movementID: owner.intent.id, lease: lease),
                  view.isHealthyRunning else { return false }
        }
        return movementAuthority.retireBinding(requestID: requestID, lease: lease, reason: reason)
    }

    private struct MovementOwnerView {
        let movementID: UUID
        let isHealthyRunning: Bool
    }

    private func movementOwner(movementID: UUID, lease: MovementTaskLease) -> MovementOwnerView? {
        let snapshot = movementAuthority.snapshot
        if let owner = routeOwners[movementID], owner.intent.lease == lease {
            return MovementOwnerView(movementID: owner.intent.id,
                isHealthyRunning: owner.begun && !owner.ended && !owner.unknown &&
                    snapshot.lease == lease && snapshot.health == .confirmedHealthy &&
                    snapshot.runState == .running)
        }
        if let owner = joystickOwners[movementID], owner.intent.lease == lease {
            return MovementOwnerView(movementID: owner.intent.id,
                isHealthyRunning: owner.prepared && owner.installed && !owner.ended &&
                    !owner.paused && !owner.neutral && owner.unknownFailure == nil &&
                    snapshot.lease == lease && snapshot.health == .confirmedHealthy &&
                    snapshot.runState == .running)
        }
        return nil
    }

    private func movementOwner(lease: MovementTaskLease) -> MovementOwnerView? {
        if let owner = routeOwners.values.first(where: { $0.intent.lease == lease }) {
            return movementOwner(movementID: owner.intent.id, lease: lease)
        }
        if let owner = joystickOwners.values.first(where: { $0.intent.lease == lease }) {
            return movementOwner(movementID: owner.intent.id, lease: lease)
        }
        return nil
    }

    /// Applies a persisted snapshot as waiting display data only. It never
    /// creates a native owner, origin proof, lease, or automatic command.
    @discardableResult public func restoreColdRecovery(position: SessionDisplayPosition?) -> Bool {
        guard !didRestoreColdRecovery, phase == .stopped, !nativeBusy,
              outstandingWork == 0, currentPoint == nil, currentPreparation == nil,
              realLocation == nil, confirmedSimulatedLocation == nil,
              clearState != .confirmed, clearConfirmedAt == nil,
              !didPerformActualOperation,
              movementAuthority.snapshot.lease == nil,
              !routeOwners.values.contains(where: { !$0.ended || $0.pendingCalls > 0 }),
              !joystickOwners.values.contains(where: { !$0.ended || $0.pendingCalls > 0 }) else { return false }
        didRestoreColdRecovery = true
        if let position {
            lastDisplayedPosition = DisplayedPosition(coordinate: position.coordinate, source: position.source)
        }
        return true
    }

    /// Marks the historical task that must be cleared before the next start.
    /// This is display state only; it does not fence native dispatch.
    public func markColdClearPending() {
        coldClearPending = true
    }

    @discardableResult
    public func beginColdClear() -> Bool {
        guard coldClearPending, phase == .stopped, !nativeBusy, outstandingWork == 0,
              clearState != .confirmed, !clearScheduled else { return false }
        coldClearAttempt = true
        beginClear()
        phase = .stopping
        nativeBusy = true
        enqueue(.stopping) { try await $0.clearLocation() }
        return true
    }

    public func finishColdClear() { coldClearPending = false }

    private func invalidateAvailableMovementGates() {
        diagnose("movement.gates.invalidated", level: .notice, [
            "preparation": .flag(currentPreparation != nil),
            "point": .flag(currentPoint != nil),
            "routes": .count(routeOwners.count),
            "joystick": .count(joystickOwners.count)
        ])
        currentPreparation?.dispatch.invalidate()
        currentPoint?.dispatch.invalidate()
        for owner in routeOwners.values {
            owner.controlRevision &+= 1
            owner.tick?.gate.invalidate()
        }
        for owner in joystickOwners.values {
            owner.inputRevision = JoystickInputRevision()
            owner.tick?.gate?.invalidate()
        }
    }

    public var displayPositionMarker: PositionMarker? {
        guard let marker = positionMarker else { return nil }
        if marker.source == .simulation, marker.freshness == .waiting,
           simulationDisplayVerified, movementConnection != .unavailable, phase == .ready,
           error == nil, movementAuthority.snapshot.runState == .running,
           movementAuthority.snapshot.health == .confirmedHealthy {
            return PositionMarker(coordinate: marker.coordinate, source: .simulation, freshness: .fresh)
        }
        return marker
    }

    public var positionMarker: PositionMarker? {
        guard let position = lastDisplayedPosition else { return nil }
        let fresh: Bool
        switch position.source {
        case .gps:
            fresh = confirmedSimulatedLocation == nil && realLocation?.coordinate == position.coordinate
        case .simulation:
            fresh = confirmedSimulatedLocation == position.coordinate && simulationDisplayVerified
                && movementConnection != .unavailable && phase != .repairRequired
        }
        return PositionMarker(coordinate: position.coordinate, source: position.source,
                              freshness: fresh ? .fresh : .waiting)
    }

    /// Read-only evidence for cold recovery. This projection observes only
    /// actual gate/pending/clear state and never performs native work.
    public var recoveryUncertainty: SessionMovementUncertainty? {
        // An accepted clear is itself the recovery boundary. Until its GPS
        // acknowledgement arrives, do not let a still-draining owner hide
        // the required recovery hold behind a lower-priority movement proof.
        if clearAttempted && clearState != .confirmed {
            return SessionMovementUncertainty(source: .gpsRecovery)
        }
        if let point = currentPoint,
           point.dispatch.hasDispatched || pointStateIsSendingOrUnconfirmed {
            return SessionMovementUncertainty(source: .point, requestedPlace: point.intent.candidate.place)
        }
        if let preparation = currentPreparation,
           case .route(let intent) = preparation.source,
           preparation.dispatch.hasDispatched {
            // Route preparation owns the first native write before a route
            // tick exists. A claimed gate is uncertainty evidence; a merely
            // queued prepare remains display-only and is intentionally absent.
            return SessionMovementUncertainty(source: .route, requestedPlace: requestedPlace(for: intent.draft))
        }
        if let owner = routeOwners.values.first(where: { routeOwnerHasUncertainty($0) }) {
            return SessionMovementUncertainty(source: .route, requestedPlace: requestedPlace(for: owner))
        }
        if joystickOwners.values.contains(where: { joystickOwnerHasUncertainty($0) }) {
            return SessionMovementUncertainty(source: .joystick, requestedPlace: nil)
        }
        return nil
    }

    private var pointStateIsSendingOrUnconfirmed: Bool {
        switch pointState {
        case .sending, .unconfirmed: return true
        default: return false
        }
    }

    private func requestedPlace(for owner: RouteOwner) -> MapPlace? {
        requestedPlace(for: owner.intent.draft)
    }

    private func requestedPlace(for draft: RouteDraft) -> MapPlace? {
        for node in draft.nodes.reversed() {
            if case .place(let place) = node.value { return place }
        }
        return nil
    }

    private func routeOwnerHasUncertainty(_ owner: RouteOwner) -> Bool {
        owner.unknown || owner.tick?.gate.hasDispatched == true
    }

    private func joystickOwnerHasUncertainty(_ owner: JoystickOwner) -> Bool {
        owner.unknownFailure != nil || owner.tick?.gate?.hasDispatched == true
    }

    /// `rebuildingConnection` is a teleport hold's resume: like every other
    /// resume it drops the possibly stale session before its first write.
    @discardableResult public func teleport(to candidate: TeleportCandidate, rebuildingConnection: Bool = false) -> Bool {
        guard canTeleport else { return false }
        admitExplicitOperation()
        if rebuildingConnection { rebuildConnectionForResume("teleport") }
        beginPreparation(.point(PointMoveIntent(candidate: candidate)))
        return true
    }

    @discardableResult public func start() -> Bool {
        guard canStart else { return false }
        // Start begins a new session: a previous Stop must not keep the pill
        // on "stopped" once preparation succeeds.
        hasSimulated = false
        if phase == .ready { return true }
        admitExplicitOperation()
        startRebuildsConnection = error != nil || deviceMayHoldSimulation
            || (clearAttempted && clearState == .unknown)
        beginPreparation(.start)
        return true
    }

    /// Warms up the device session in the background without affecting preparation UI or phase state,
    /// eliminating connection latency when switching to joystick mode or starting movement.
    public func warmupSession() {
        guard !nativeBusy, movementAdmissionAllowed, phase == .ready || phase == .stopped else { return }
        enqueueAdapter({ service in
            do {
                try await service.prepare()
                return .success
            } catch {
                return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable)
            }
        }) { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                self.diagnoseResult("warmupSession.failure", result, op: "warmup", matched: true, outstanding: self.outstandingWork)
            }
        }
    }

    @discardableResult public func cancelPreparation(id: UUID) -> Bool {
                if !nativeBusy, let snapshot = preparedOperation, snapshot.id == id, case .failed = snapshot.state {
            if case .route(let intent) = snapshot.source { endRoute(executionID: intent.id, lease: intent.lease) }
            if case .joystick(let intent) = snapshot.source, let owner = joystickOwners[intent.id] { cancelJoystickOwner(owner) }
            preparedOperation = nil
            return true
        }
        guard let context = currentPreparation, context.id == id,
              let snapshot = preparedOperation, snapshot.state == .preparing,
              context.dispatch.invalidateIfAvailable() else { return false }
        revision &+= 1
        watchdog?.cancel()
        preparedOperation = PreparedOperationSnapshot(id: id, source: context.source,
            attempt: snapshot.attempt, state: .cancelled)
        currentPoint = nil
        if case .point(let intent) = context.source { pointState = .notSent(intent, .operationCancelled) }
        if case .route(let intent) = context.source, let owner = routeOwners[intent.id] {
            owner.ended = true
            movementAuthority.revoke(intent.lease)
            routeSubject.send(.ended(intent.id))
            settle(owner)
        }
        if case .joystick(let intent) = context.source, let owner = joystickOwners[intent.id] { cancelJoystickOwner(owner) }
        phase = context.wasReady ? .ready : .stopped
        error = nil
        return true
    }

    @discardableResult public func retryPreparedOperation(id: UUID) -> Bool {
        guard !nativeBusy, movementAdmissionAllowed, !pointUnconfirmed, let snapshot = preparedOperation,
              snapshot.id == id, case .failed = snapshot.state else { return false }
        if case .route(let intent) = snapshot.source {
            guard let owner = routeOwners[intent.id], !owner.ended, !owner.unknown, owner.begin != nil,
                  !routeUnconfirmed, (phase == .ready || phase == .stopped) else { return false }
        }
        if case .joystick(let intent) = snapshot.source {
            guard let owner = joystickOwners[intent.id], !owner.ended, owner.begin != nil else { return false }
        }
        beginPreparation(snapshot.source)
        return true
    }

    private func beginPreparation(_ source: PreparedOperationSource) {
        let lease: MovementTaskLease
        if case .route(let intent) = source { lease = intent.lease } else { lease = MovementTaskLease() }
        let dispatch = makePreparationGate(source, lease: lease)
        let context = PreparationContext(id: UUID(), source: source, dispatch: dispatch,
            wasReady: phase == .ready, displayEpoch: simulationDisplayEpoch)
        currentPreparation = context
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: source, attempt: .first, state: .preparing)
        let point: PointContext?
        if case .point(let intent) = source {
            point = PointContext(intent: intent, dispatch: dispatch, wasReady: context.wasReady,
                lease: lease, displayEpoch: context.displayEpoch, admissionRevision: routeAdmissionRevision)
            currentPoint = point; pointState = .preparing(intent)
        } else { point = nil }
        let token = beginLifecycle(.preparing, point: point, preparation: context)
        enqueuePreparationAttempt(context, attempt: .first, token: token, point: point)
    }

    private func makePreparationGate(_ source: PreparedOperationSource, lease: MovementTaskLease) -> PointDispatchGate {
        let callback: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                switch source {
                case .start, .joystick: break
                case .point(let intent): self?.pointDidDispatch(intent.id)
                case .route(let intent): self?.routeDidDispatch(intent)
                }
            }
        }
        switch source {
        case .start, .joystick: return PointDispatchGate(onDispatch: callback)
        default: break
        }
        return PointDispatchGate(authority: movementAuthority, lease: lease,
            replacing: movementAuthority.snapshot, onDispatch: callback)
    }

    private func enqueuePreparationAttempt(_ context: PreparationContext, attempt: PreparationAttempt,
                                            token: UInt64, point: PointContext?) {
        let owner: RouteOwner?
        if case .route(let intent) = context.source { owner = routeOwners[intent.id] } else { owner = nil }
        let joystick: JoystickOwner?
        if case .joystick(let intent) = context.source { joystick = joystickOwners[intent.id] } else { joystick = nil }
        owner?.pendingCalls += 1
        joystick?.pendingCalls += 1
        enqueueAdapter({ [weak self] service in
            guard let self, self.revision == token, self.preparationIsCurrent(context) else { return .failure(.operationCancelled) }
            self.publishAttempt(attempt, context: context)
            switch context.source {
            case .start:
                guard self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                // Start owns tunnel repair: leftovers from the last session or a
                // failed attempt discard the old connection before preparing.
                let rebuild = attempt != .first || self.startRebuildsConnection
                do {
                    if rebuild { try await service.rebuildClientConnection() }
                    try await service.prepare()
                    return .success
                }
                catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
            case .joystick:
                guard self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                do { try await service.prepare(); return .success }
                catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
            case .point(let intent):
                guard self.movementAdmissionAllowed else { return .point(.notSent(.operationCancelled)) }
                return .point(await service.movePoint(to: intent.candidate.place.coordinate, dispatch: context.dispatch))
            case .route(let intent):
                guard self.movementAdmissionAllowed else { return .point(.notSent(.operationCancelled)) }
                return .point(await service.movePoint(to: intent.route.start, dispatch: context.dispatch))
            }
        }) { [weak self] result in
            guard let self else { return }
            owner?.pendingCalls -= 1
            joystick?.pendingCalls -= 1
            self.diagnoseResult("preparation.attempt", result, op: context.source.diagnosticsLabel,
                                matched: true, outstanding: self.outstandingWork)
            if let owner { self.quarantineCancelledRouteWrite(owner, gate: context.dispatch, result: result) }
            let retryable: Bool
            switch result {
            case .failure: retryable = true
            case .point(.notSent): retryable = true
            default: retryable = false
            }
            // Point delivery already owns one session rebuild/retry inside
            // the device adapter. Do not multiply it with preparation rounds.
            let adapterOwnsPointRetry: Bool
            if case .point = context.source { adapterOwnsPointRetry = true }
            else { adapterOwnsPointRetry = false }
            if retryable, !adapterOwnsPointRetry,
               self.revision == token, self.preparationIsCurrent(context),
               let next = attempt.next {
                // Requeue behind already waiting healthy old ticks, never hold the pump for a whole round.
                self.enqueuePreparationAttempt(context, attempt: next, token: token, point: point)
            } else {
                self.complete(.preparing, token: token, result: result, point: point,
                              preparation: context)
            }
            if let owner { self.settle(owner) }
            if let joystick { self.settleJoystick(joystick) }
        }
    }

    private func preparationIsCurrent(_ context: PreparationContext) -> Bool {
        currentPreparation?.id == context.id && preparedOperation?.state == .preparing && context.dispatch.state == .available
    }

    private func publishAttempt(_ attempt: PreparationAttempt, context: PreparationContext) {
        guard preparationIsCurrent(context) else { return }
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: context.source, attempt: attempt, state: .preparing)
    }

    /// Safety cleanup is unconditional FIFO work. Invalidation can skip a point
    /// before dispatch but cannot cancel an FFI call that already owns handles.
    @discardableResult public func stop() -> Bool {
        guard canStop else { return false }
        endMovementForClear()
        enqueue(.stopping) { try await $0.clearLocation() }
        return true
    }

    /// Forced Stop: ends every task locally at once, then tries a fresh
    /// connection and a GPS clear. A failure there only leaves GPS unknown.
    @discardableResult public func forceReset() -> Bool {
        guard canForceReset else { return false }
        diagnose("reset.forced", level: .notice, ["phase": .text(phase.rawValue)])
        endMovementForClear()
        enqueue(.stopping) { service in
            try? await service.rebuildClientConnection()
            try await service.clearLocation()
        }
        forcedResetToken = revision
        return true
    }

    private func endMovementForClear() {
        cancelConnectionRecovery()
        routeStopGeneration &+= 1
        routeAdmissionRevision &+= 1
        nativeBusy = true
        beginClear()
        phase = .stopping
        for owner in Array(routeOwners.values) { endRoute(executionID: owner.intent.id, lease: owner.intent.lease) }
        routeUnconfirmed = false
        joystickUnconfirmed = false
        for owner in Array(joystickOwners.values) { cancelJoystickOwner(owner) }
        movementAuthority.revokeAll()
        joystickSubject.send(.movementBoundary(nil))
        currentPreparation?.dispatch.invalidate()
        currentPreparation = nil
        preparedOperation = nil
        currentPoint?.dispatch.invalidate()
        currentPoint = nil
        pointState = .idle
    }

    @discardableResult public func restoreGPS() -> Bool {
        guard canRestoreGPS else { return false }
        admitExplicitOperation()
        beginClear()
        enqueue(.restoring) { try await $0.clearLocation() }
        return true
    }

    private func beginClear() {
        diagnose("clear.scheduled", level: .notice,
                 ["phase": .text(phase.rawValue), "cold": .flag(coldClearAttempt)])
        clearScheduled = true
        clearAttempted = true
        clearState = .pending
        clearConfirmedAt = nil
        realLocation = nil
        confirmedSimulatedLocation = nil
    }

    /// Ends simulation while retaining the prepared connection. GPS restore
    /// remains an explicit separate operation.
    @discardableResult public func stopSimulation() -> Bool {
        guard canStop else { return false }
        cancelConnectionRecovery()
        revision &+= 1
        watchdog?.cancel()
        routeStopGeneration &+= 1
        for owner in Array(routeOwners.values) { endRoute(executionID: owner.intent.id, lease: owner.intent.lease) }
        for owner in Array(joystickOwners.values) { cancelJoystickOwner(owner) }
        movementAuthority.revokeAll()
        joystickSubject.send(.movementBoundary(nil))
        currentPoint?.dispatch.invalidate()
        currentPoint = nil
        currentPreparation?.dispatch.invalidate()
        currentPreparation = nil
        preparedOperation = nil
        pointState = .idle
        markSimulationPositionUnverified()
        // Stop ends simulation for the user: nothing takes over or keeps the
        // last position alive, even before Restore clears the device.
        deviceMayHoldSimulation = false
        hasSimulated = true
        phase = .ready
        error = nil
        return true
    }

    @discardableResult
    public func requestConnectionRecovery(failure: DeviceServiceFailure, explicitlyRequested: Bool = false) -> Bool {
        guard [.tunnelUnavailable, .serviceUnavailable, .operationTimedOut].contains(failure) else { return false }
        if connectionRecovery != nil { return true }
        let snapshot = movementAuthority.snapshot
        guard let lease = snapshot.lease,
              (snapshot.runState == .running || (explicitlyRequested && snapshot.runState == .paused)),
              let position = lastDisplayedPosition, position.source == .simulation else { return false }
        let executionID = routeOwners.values.first { $0.intent.lease == lease && !$0.ended }?.intent.id
            ?? joystickOwners.values.first { $0.intent.lease == lease && !$0.ended }?.intent.id
        guard let executionID else { return false }
        let recovery = MovementConnectionRecovery(id: UUID(), executionID: executionID,
            lease: lease, coordinate: position.coordinate, failure: failure, resumesTask: snapshot.runState == .running,
            explicitlyRequested: explicitlyRequested)
        connectionRecovery = recovery
        guard connectionRecoveryRequested?(recovery) == true else {
            connectionRecovery = nil
            return false
        }
        isRecoveringConnection = true
        error = failure
        setMovementConnectionAvailable(false)
        return true
    }

    public func cancelConnectionRecovery() {
        guard let recovery = connectionRecovery ?? failedConnectionRecovery else { return }
        failedConnectionRecovery = nil
        connectionRecoveryGate?.invalidate()
        connectionRecoveryGate = nil
        connectionRecovery = nil
        isRecoveringConnection = false
        movementAuthority.updateRunState(.paused, for: recovery.lease)
        if let owner = joystickOwners[recovery.executionID] {
            owner.paused = true; owner.neutral = false; owner.disposition = nil
        }
    }

    /// Runs behind existing native work; never clears GPS or replaces the
    /// logical movement owner. Only the repair ACK reopens ordinary dispatch.
    public func repairConnection(_ recovery: MovementConnectionRecovery) async -> Bool {
        guard connectionRecovery == recovery else { return false }
        let gate = PointDispatchGate(repairingConnection: movementAuthority, lease: recovery.lease, allowingPaused: !recovery.resumesTask)
        connectionRecoveryGate = gate
        let token = beginLifecycle(.resetting, point: nil, preparation: nil)
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] device in
                guard let self, self.connectionRecovery == recovery else { return .failure(.operationCancelled) }
                do {
                    try await device.rebuildClientConnection()
                    try await device.prepare()
                    guard self.connectionRecovery == recovery else { return .success }
                    return .point(await device.movePoint(to: recovery.coordinate, dispatch: gate))
                } catch {
                    return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable)
                }
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: false); return }
                self.outstandingWork -= 1
                self.nativeBusy = self.outstandingWork > 0 || self.hasPendingRouteRepair
                guard self.connectionRecovery == recovery, self.revision == token else {
                    if self.connectionRecovery == recovery {
                        // A real lifecycle timeout may finish before native
                        // work drains. Once it has returned, Retry can start
                        // a fresh attempt rather than reusing the expired one.
                        gate.invalidate()
                        self.connectionRecovery = nil
                        self.connectionRecoveryGate = nil
                        self.isRecoveringConnection = false
                        self.failedConnectionRecovery = recovery
                    }
                    if self.phase == .resetting { self.phase = .ready }
                    if case .success = result, self.phase == .ready {
                        self.setMovementConnectionAvailable(true)
                        self.error = nil
                    }
                    continuation.resume(returning: false)
                    return
                }
                self.watchdog?.cancel()
                self.connectionRecovery = nil
                self.connectionRecoveryGate = nil
                self.isRecoveringConnection = false
                if case .point(.acknowledged) = result, gate.hasDispatched {
                    self.failedConnectionRecovery = nil
                    self.routeUnconfirmed = false
                    self.joystickUnconfirmed = false
                    if let owner = self.routeOwners[recovery.executionID] {
                        owner.unknown = false; owner.unknownFailure = nil; owner.interrupted = false
                    }
                    if let owner = self.joystickOwners[recovery.executionID] {
                        owner.unknownFailure = nil
                    }
                    self.movementAuthority.updateHealth(.confirmedHealthy, for: recovery.lease)
                    self.setMovementConnectionAvailable(true)
                    self.publishSimulation(recovery.coordinate, displayEpoch: self.simulationDisplayEpoch)
                    self.phase = .ready; self.error = nil
                    continuation.resume(returning: true)
                } else {
                    self.failedConnectionRecovery = recovery
                    self.phase = .repairRequired
                    switch result {
                    case .failure(let failure), .point(.notSent(let failure)), .point(.unconfirmed(let failure)):
                        self.error = failure
                    default: self.error = .serviceUnavailable
                    }
                    self.markSimulationPositionUnverified()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// GPS remains independent evidence; active simulation takes display priority.
    public func observeRealLocation(_ observation: RealLocationObservation?) {
        let originsBefore = originAvailability
        var pointDispatched = false
        if let point = currentPoint, point.dispatch.hasDispatched {
            pointDidDispatch(point.intent.id)
            pointDispatched = true
        }
        guard let observation,
              observation.observedAt <= now(),
              now().timeIntervalSince(observation.observedAt) <= 15 else {
            realLocation = nil
            return
        }
        realLocation = observation
        // A fix that only refreshes an origin already available changes nothing
        // route or joystick can act on, so it does not wake their observers.
        if pointDispatched || originAvailability != originsBefore {
            routeSubject.send(.availabilityChanged)
            joystickSubject.send(.availabilityChanged)
        }
        if confirmedSimulatedLocation == nil {
            lastDisplayedPosition = DisplayedPosition(coordinate: observation.coordinate, source: .gps)
        }
    }

    private var originAvailability: (route: Bool, joystick: Bool) {
        (currentRouteOrigin != nil, currentJoystickOrigin != nil)
    }

    private func pointDidDispatch(_ id: UUID) {
        guard currentPoint?.intent.id == id,
              case .preparing(let intent) = pointState, intent.id == id else { return }
        pointState = .sending(intent)
        preparedOperation = nil
        if phase == .preparing { phase = .ready }
        realLocation = nil
        confirmedSimulatedLocation = nil
        // A new point write supersedes prior evidence that simulation was cleared.
        clearState = .unknown
        clearConfirmedAt = nil
        clearAttempted = false
        endSupersededRoutes()
    }

    private func enqueue(
        _ operation: ServicePhase,
        work: @escaping @Sendable (any DeviceService) async throws -> Void
    ) {
        enqueueCommand(operation) { service in
            do { try await work(service); return .success }
            catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
        }
    }

    private func enqueueCommand(
        _ operation: ServicePhase, point: PointContext? = nil, preparation: PreparationContext? = nil,
        work: @escaping @MainActor @Sendable (any DeviceService) async -> CommandResult
    ) {
        let token = beginLifecycle(operation, point: point, preparation: preparation)
        enqueueAdapter(work) { [weak self] result in
            self?.complete(operation, token: token, result: result, point: point,
                           preparation: preparation)
        }
    }

    private func beginLifecycle(_ operation: ServicePhase, point: PointContext?, preparation: PreparationContext?) -> UInt64 {
        revision &+= 1
        let token = revision
        phase = operation
        diagnose("phase.enter", level: .notice, [
            "op": .text(operation.rawValue),
            "token": .count(Int(truncatingIfNeeded: token)),
            "was": .text(phase == operation ? "same" : "changed")
        ])
        error = nil
        nativeBusy = true
        outstandingWork += 1
        watchdog?.cancel()
        let timeout = operationTimeout
        let watchdogSleep = self.watchdogSleep
        watchdog = Task { [weak self] in
            do { try await watchdogSleep(timeout) } catch { return }
            guard let self, self.revision == token, self.nativeBusy else { return }
            self.diagnose("watchdog.fired", level: .error, [
                "op": .text(operation.rawValue),
                "token": .count(Int(truncatingIfNeeded: token)),
                "timeout_s": .number(Double(timeout.components.seconds), digits: 0),
                "point": .flag(point != nil),
                "preparation": .flag(preparation != nil),
                "dispatched": .flag(point?.dispatch.hasDispatched ?? preparation?.dispatch.hasDispatched ?? false)
            ])
            self.revision &+= 1
            self.phase = .repairRequired
            self.error = .operationTimedOut
            if let preparation, self.currentPreparation?.id == preparation.id {
                preparation.dispatch.invalidate()
                if !preparation.dispatch.hasDispatched {
                    if preparation.wasReady { self.phase = .ready }
                    self.preparedOperation = PreparedOperationSnapshot(id: preparation.id, source: preparation.source,
                        attempt: self.preparedOperation?.attempt ?? .first, state: .failed(.operationTimedOut))
                }
            }
            if let point {
                point.dispatch.invalidate()
                if point.dispatch.hasDispatched {
                    self.pointDidDispatch(point.intent.id)
                    self.pointState = .unconfirmed(point.intent, .operationTimedOut)
                    self.movementAuthority.updateHealth(.unknown, for: point.lease)
                } else {
                    self.pointState = .notSent(point.intent, .operationTimedOut)
                }
            }
            if let preparation, case .route(let intent) = preparation.source,
               preparation.dispatch.hasDispatched, let owner = self.routeOwners[intent.id], !owner.ended {
                self.markRouteUnknown(owner, failure: .operationTimedOut)
                self.resolveBegin(owner, outcome: .unconfirmed(.operationTimedOut))
            }
            if operation == .stopping || operation == .restoring {
                self.clearState = .unknown
            }
            // Only actual completion releases nativeBusy and permits FIFO clear.
        }
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
        return token
    }

    private func enqueueAdapter(_ work: @escaping @MainActor @Sendable (any DeviceService) async -> CommandResult,
                                completion: @escaping @MainActor (CommandResult) -> Void) {
        adapterQueue.append(AdapterCommand(work: work, completion: completion))
        guard !pumping else { return }
        pumping = true
        Task { [weak self] in
            guard let self else { return }
            while !self.adapterQueue.isEmpty {
                let command = self.adapterQueue.removeFirst()
                let result = await command.work(self.service)
                // Completion and any retry requeue finish before the next adapter call.
                command.completion(result)
            }
            self.pumping = false
        }
    }

    private func complete(
        _ operation: ServicePhase, token: UInt64,
        result: CommandResult, point: PointContext?, preparation: PreparationContext?
    ) {
        outstandingWork -= 1
        diagnoseResult("phase.exit", result, op: operation.rawValue,
                       matched: token == revision, outstanding: outstandingWork)
        if operation == .stopping || operation == .restoring { clearScheduled = false }
        if token == revision {
            watchdog?.cancel()
            switch result {
            case .success:
                if preparation != nil { preparedOperation = nil }
                phase = operation == .preparing ? .ready : .stopped
                error = nil
                if let preparation, case .joystick(let intent) = preparation.source,
                   let owner = joystickOwners[intent.id], !owner.ended, owner.unknownFailure == nil {
                    owner.prepared = true
                    resolveJoystickBeginning(owner, outcome: .prepared)
                }
                if operation == .stopping || operation == .restoring {
                    coldClearAttempt = false
                    deviceMayHoldSimulation = false
                    clearState = .confirmed
                    clearConfirmedAt = now()
                }
            case .failure(let failure):
                if operation == .stopping, coldClearAttempt || forcedResetToken == token {
                    coldClearAttempt = false
                    phase = .stopped
                    error = nil
                    clearState = .unknown
                    clearConfirmedAt = nil
                } else {
                    if let preparation { failPreparation(preparation, failure: failure) }
                    phase = preparation?.wasReady == true ? .ready : .stopped
                    error = failure
                    if operation == .stopping || operation == .restoring {
                        clearState = .unknown
                        clearConfirmedAt = nil
                    }
                }
            case .point(let outcome):
                if let point { completePoint(point, outcome: outcome) }
                if let preparation, case .route(let intent) = preparation.source,
                   let owner = routeOwners[intent.id], !owner.ended {
                    completeRouteBeginning(owner, context: preparation, outcome: outcome)
                }
                if let preparation, !preparation.dispatch.hasDispatched, case .notSent(let failure) = outcome {
                    failPreparation(preparation, failure: failure)
                }
            }
        }
        if forcedResetToken == token { forcedResetToken = nil }
        if preparation?.source == .start { startRebuildsConnection = false }
        if let preparation, currentPreparation?.id == preparation.id {
            currentPreparation = nil
            if preparedOperation?.state == .cancelled { preparedOperation = nil }
        }
        if let point, currentPoint?.intent.id == point.intent.id { currentPoint = nil }
        if outstandingWork == 0 {
            nativeBusy = hasPendingRouteRepair
            if phase == .repairRequired && !pointUnconfirmed && !routeUnconfirmed && !joystickUnconfirmed { phase = .stopped }
        }
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    private func failPreparation(_ context: PreparationContext, failure: DeviceServiceFailure) {
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: context.source,
            attempt: preparedOperation?.attempt ?? .first, state: .failed(failure))
    }

    private func completePoint(_ point: PointContext, outcome: PointDeliveryOutcome) {
        if point.dispatch.hasDispatched { pointDidDispatch(point.intent.id) }
        diagnoseResult("point.outcome", .point(outcome), op: "point",
                       matched: true, outstanding: outstandingWork, level: .notice)
        switch outcome {
        case .notSent(let failure):
            if point.dispatch.hasDispatched {
                pointState = .unconfirmed(point.intent, failure)
                movementAuthority.updateHealth(.unknown, for: point.lease)
                phase = .repairRequired
            } else {
                pointState = .notSent(point.intent, failure)
                phase = point.wasReady ? .ready : .stopped
            }
            error = failure
        case .acknowledged:
            preparedOperation = nil
            point.dispatch.invalidate()
            guard point.dispatch.hasDispatched else {
                pointState = .unconfirmed(point.intent, .serviceUnavailable)
                movementAuthority.revokeAll()
                phase = .repairRequired
                error = .serviceUnavailable
                return
            }
            movementAuthority.updateHealth(.confirmedHealthy, for: point.lease)
            publishSimulation(point.intent.candidate.place.coordinate, displayEpoch: point.displayEpoch)
            pointState = .acknowledged(point.intent)
            phase = .ready
            error = nil
            teleportAcknowledgementSubject.send(TeleportAcknowledgement(
                intent: point.intent, lease: point.lease, displayEpoch: point.displayEpoch,
                admissionRevision: point.admissionRevision))
        case .unconfirmed(let failure):
            preparedOperation = nil
            point.dispatch.invalidate()
            if point.dispatch.hasDispatched { movementAuthority.updateHealth(.unknown, for: point.lease) }
            else { movementAuthority.revokeAll() }
            pointState = .unconfirmed(point.intent, failure)
            phase = .repairRequired
            error = failure
        }
    }
}

extension ServiceController {
    public var canBeginRoute: Bool { canTeleport }
    public var routeEvents: AnyPublisher<RouteCommandEvent, Never> { routeSubject.eraseToAnyPublisher() }
    public var currentRouteOrigin: GeoCoordinate? {
        if let confirmedSimulatedLocation { return confirmedSimulatedLocation }
        guard let realLocation, realLocation.observedAt <= now(), now().timeIntervalSince(realLocation.observedAt) <= 15 else { return nil }
        return realLocation.coordinate
    }
    public func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome {
        guard expectedAdmissionRevision == routeAdmissionRevision, canBeginRoute, routeOwners[intent.id] == nil else { return .cancelled }
        admitExplicitOperation()
        return await withCheckedContinuation { continuation in
            let owner = RouteOwner(intent, stopGeneration: routeStopGeneration, begin: continuation)
            routeOwners[intent.id] = owner
            beginPreparation(.route(intent))
        }
    }
    public func routeControlRevision(executionID: UUID, lease: MovementTaskLease) -> UInt64? {
        eligibleRouteControlOwner(executionID: executionID, lease: lease)?.controlRevision
    }
    public func reviseRouteControl(executionID: UUID, lease: MovementTaskLease) -> UInt64? {
                guard let owner = eligibleRouteControlOwner(executionID: executionID, lease: lease) else { return nil }
        owner.controlRevision &+= 1
        if let tick = owner.tick, tick.gate.invalidateIfAvailable() {
            tick.controlCancelled = true
            tick.watchdog?.cancel()
        }
        return owner.controlRevision
    }
    private func eligibleRouteControlOwner(executionID: UUID, lease: MovementTaskLease) -> RouteOwner? {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun,
              !owner.ended, !owner.unknown, movementAuthority.snapshot.lease == lease,
              movementAuthority.snapshot.health == .confirmedHealthy, !routeUnconfirmed, !joystickUnconfirmed else { return nil }
        return owner
    }
    public func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64,
                               coordinate: GeoCoordinate) async -> RouteCommandOutcome {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun,
              !owner.ended, !owner.unknown, owner.tick == nil,
              owner.lastSequence < UInt64.max, sequence == owner.lastSequence + 1,
              movementAdmissionAllowed, !routeUnconfirmed, !joystickUnconfirmed else { return .cancelled }
        guard movementAuthority.permitsDispatch(for: lease) else {
            _ = pauseExpiredContinuation(movementID: executionID, lease: lease,
                result: .point(.notSent(.operationCancelled)))
            return .cancelled
        }
        guard owner.controlRevision == expectedControlRevision else { return .controlCancelled }
        let gate = PointDispatchGate(authority: movementAuthority, lease: lease) { [weak self] in
            Task { @MainActor in self?.routeTickDidDispatch(executionID: executionID, sequence: sequence) }
        }
        let tick = RouteTick(gate: gate, coordinate: coordinate, sequence: sequence,
            displayEpoch: simulationDisplayEpoch)
        owner.tick = tick; owner.pendingCalls += 1
        let tickStarted = DispatchTime.now().uptimeNanoseconds
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] service in
                guard let self, self.routeTickIsCurrent(owner, tick), self.movementAdmissionAllowed,
                      self.movementAuthority.permitsDispatch(for: lease), !self.joystickUnconfirmed else {
                    tick.skipped = true
                    return .point(.notSent(.operationCancelled))
                }
                if tick.controlCancelled { return .point(.notSent(.operationCancelled)) }
                tick.watchdog = Task { [weak self] in
                    guard let self, !tick.controlCancelled else { return }
                    do { try await self.watchdogSleep(self.operationTimeout) } catch { return }
                    guard self.routeTickIsCurrent(owner, tick), !owner.ended, !tick.controlCancelled,
                          self.movementAuthority.snapshot.lease == lease else { return }
                    if !tick.gate.hasDispatched, self.movementAuthority.snapshot.runState != .running { return }
                    self.diagnose("watchdog.fired", level: .error, [
                        "op": .text("route.tick"),
                        "seq": .count(Int(truncatingIfNeeded: sequence)),
                        "timeout_s": .number(Double(self.operationTimeout.components.seconds), digits: 0),
                        "dispatched": .flag(tick.gate.hasDispatched)
                    ])
                    tick.timedOut = true; tick.gate.invalidate()
                    if tick.gate.hasDispatched {
                        self.routeTickDidDispatch(executionID: executionID, sequence: sequence)
                        self.markRouteUnknown(owner, failure: .operationTimedOut)
                    } else { self.markRouteInterrupted(owner, failure: .operationTimedOut) }
                }
                return .point(await service.movePoint(to: coordinate, dispatch: gate))
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: .cancelled); return }
                tick.watchdog?.cancel()
                self.diagnoseResult("route.tick", result, op: "route",
                                    matched: true, outstanding: self.outstandingWork,
                                    extra: ["seq": .count(Int(truncatingIfNeeded: sequence)),
                                            "ms": .milliseconds(elapsedMilliseconds(since: tickStarted)),
                                            "dispatched": .flag(tick.gate.hasDispatched)])
                let outcome = self.completeRouteTick(owner, tick: tick, result: result)
                owner.tick = nil; owner.pendingCalls -= 1
                self.nativeBusy = self.outstandingWork > 0 || self.hasPendingRouteRepair
                continuation.resume(returning: outcome)
                self.settle(owner)
                self.routeSubject.send(.availabilityChanged)
            }
        }
    }
    public func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun, !owner.ended, !owner.unknown,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.updateRunState(.paused, for: lease) else { return false }
        owner.tick?.gate.invalidate()
        return true
    }
    public func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun, !owner.ended, !owner.unknown,
              owner.tick == nil, movementAuthority.snapshot.lease == lease,
              !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.health == .confirmedHealthy,
              movementAuthority.snapshot.runState == .paused else { return false }
        guard movementAuthority.resumeForeground(lease) else { return false }
        rebuildConnectionForResume("route")
        return true
    }
    public func endRoute(executionID: UUID, lease: MovementTaskLease) {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease else { return }
        if !owner.ended {
            if let tick = owner.tick, tick.gate.hasDispatched { routeTickDidDispatch(executionID: executionID, sequence: tick.sequence) }
            if let context = currentPreparation, case .route(let intent) = context.source, intent.id == executionID {
                if context.dispatch.hasDispatched { routeDidDispatch(intent) }
                context.dispatch.invalidate(); revision &+= 1; watchdog?.cancel()
                currentPreparation = nil; preparedOperation = nil
                if !clearScheduled { phase = context.wasReady || context.dispatch.hasDispatched ? .ready : .stopped }
            }
            if let snapshot = preparedOperation, case .route(let intent) = snapshot.source, intent.id == executionID { preparedOperation = nil }
            owner.ended = true; owner.tick?.gate.invalidate()
            movementAuthority.revoke(lease)
            nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
            routeSubject.send(.ended(executionID))
        } else if clearScheduled {
            routeSubject.send(.ended(executionID))
        }
        settle(owner)
    }
    public func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease else { return .settled }
        guard owner.pendingCalls > 0 else { return idleSettlement(owner) }
        return await withCheckedContinuation { owner.idle.append($0) }
    }

    private var hasPendingRouteRepair: Bool {
        routeOwners.values.contains { ($0.unknown || $0.interrupted || $0.ended) && $0.pendingCalls > 0 }
            || joystickOwners.values.contains { ($0.ended || $0.disposition != nil || $0.unknownFailure != nil || $0.tick?.timedOut == true) && $0.pendingCalls > 0 }
    }
    private func admitExplicitOperation() {
        didPerformActualOperation = true
        routeAdmissionRevision &+= 1
        // An accepted user operation fences maintenance before its new gate
        // is captured. Already claimed calls still settle on the same FIFO.
        for owner in Array(joystickOwners.values) where owner.intent.fixedPosition != nil && !owner.ended {
            if movementAuthority.snapshot.lease == owner.intent.lease {
                markSimulationPositionUnverified()
            }
            cancelJoystickOwner(owner)
        }
        // A failed route preparation may still be awaiting user Retry/Cancel.
        for owner in Array(routeOwners.values) where owner.begin != nil {
            endRoute(executionID: owner.intent.id, lease: owner.intent.lease)
        }
        for owner in Array(joystickOwners.values) where owner.begin != nil { cancelJoystickOwner(owner) }
    }
    private func routeDidDispatch(_ intent: RouteExecutionIntent) {
        guard !clearScheduled, let context = currentPreparation, case .route(let stored) = context.source,
              stored.id == intent.id, context.dispatch.hasDispatched, preparedOperation?.state == .preparing,
              let owner = routeOwners[intent.id], !owner.ended else { return }
        preparedOperation = nil
        if phase == .preparing { phase = .ready }
        invalidatePositionProof()
        endSupersededRoutes()
    }
    private func invalidatePositionProof() {
        realLocation = nil; confirmedSimulatedLocation = nil
        clearState = .unknown; clearConfirmedAt = nil; clearAttempted = false
    }
    private func endSupersededRoutes() {
        let lease = movementAuthority.snapshot.lease
        for owner in Array(routeOwners.values) where owner.begun && owner.intent.lease != lease {
            endRoute(executionID: owner.intent.id, lease: owner.intent.lease)
        }
        for owner in Array(joystickOwners.values) where owner.installed && owner.intent.lease != lease {
            cancelJoystickOwner(owner)
        }
        if let lease { joystickSubject.send(.movementBoundary(lease)) }
    }
    private func completeRouteBeginning(_ owner: RouteOwner, context: PreparationContext, outcome: PointDeliveryOutcome) {
        if context.dispatch.hasDispatched { routeDidDispatch(owner.intent) }
        switch outcome {
        case .notSent(let failure) where !context.dispatch.hasDispatched:
            phase = context.wasReady ? .ready : .stopped
            error = failure
        case .acknowledged where context.dispatch.hasDispatched:
            movementAuthority.updateHealth(.confirmedHealthy, for: owner.intent.lease)
            owner.begun = true
            publishSimulation(owner.intent.route.start, displayEpoch: context.displayEpoch)
            phase = .ready; error = nil; preparedOperation = nil
            resolveBegin(owner, outcome: .acknowledged)
        case .notSent(let failure), .unconfirmed(let failure):
            context.dispatch.invalidate(); preparedOperation = nil
            markRouteUnknown(owner, failure: failure)
            resolveBegin(owner, outcome: .unconfirmed(failure))
        case .acknowledged:
            context.dispatch.invalidate(); preparedOperation = nil
            markRouteUnknown(owner, failure: .serviceUnavailable)
            resolveBegin(owner, outcome: .unconfirmed(.serviceUnavailable))
        }
    }
    private func publishSimulation(_ coordinate: GeoCoordinate, displayEpoch: UUID) {
        hasSimulated = true
        deviceMayHoldSimulation = true
        confirmedSimulatedLocation = coordinate
        lastDisplayedPosition = DisplayedPosition(coordinate: coordinate, source: .simulation)
        simulationDisplayVerified = displayEpoch == simulationDisplayEpoch && movementConnection != .unavailable &&
            (movementAuthority.isSceneActive || hasBackgroundSimulationRuntime)
    }
    private func routeTickIsCurrent(_ owner: RouteOwner, _ tick: RouteTick) -> Bool {
        routeOwners[owner.intent.id] === owner && owner.tick === tick && !owner.ended && !owner.unknown
    }
    private func routeTickDidDispatch(executionID: UUID, sequence: UInt64) {
        guard !clearScheduled, let owner = routeOwners[executionID], !owner.ended,
              let tick = owner.tick, tick.sequence == sequence, tick.gate.hasDispatched,
              !tick.didInvalidateProof, movementAuthority.snapshot.lease == owner.intent.lease else { return }
        tick.didInvalidateProof = true
        invalidatePositionProof()
    }
    private func completeRouteTick(_ owner: RouteOwner, tick: RouteTick, result: CommandResult) -> RouteCommandOutcome {
        quarantineCancelledRouteWrite(owner, gate: tick.gate, result: result)
        guard routeOwners[owner.intent.id] === owner, !owner.ended,
              movementAuthority.snapshot.lease == owner.intent.lease else { return .cancelled }
        if tick.timedOut { return tick.gate.hasDispatched ? .unconfirmed(.operationTimedOut) : .notSent(.operationTimedOut) }
        guard !owner.unknown else { return .unconfirmed(error ?? .serviceUnavailable) }
        if !tick.gate.hasDispatched,
           pauseExpiredContinuation(movementID: owner.intent.id, lease: owner.intent.lease, result: result) {
            return .cancelled
        }
        if tick.skipped { return .cancelled }
        if tick.gate.hasDispatched { routeTickDidDispatch(executionID: owner.intent.id, sequence: tick.sequence) }
        let outcome: PointDeliveryOutcome
        switch result {
        case .point(let value): outcome = value
        case .failure(let failure): outcome = .notSent(failure)
        case .success: outcome = .unconfirmed(.serviceUnavailable)
        }
        switch outcome {
        case .acknowledged where tick.gate.hasDispatched:
            owner.lastSequence = tick.sequence
            publishSimulation(tick.coordinate, displayEpoch: tick.displayEpoch)
            return .acknowledged
        case .notSent(let failure) where !tick.gate.hasDispatched:
            if movementAuthority.snapshot.runState != .running { return .cancelled }
            if tick.controlCancelled { return .controlCancelled }
            if tick.gate.state == .invalidated { return .cancelled }
            markRouteInterrupted(owner, failure: failure)
            return .notSent(failure)
        case .notSent(let failure), .unconfirmed(let failure):
            markRouteUnknown(owner, failure: failure)
            return .unconfirmed(failure)
        case .acknowledged:
            markRouteUnknown(owner, failure: .serviceUnavailable)
            return .unconfirmed(.serviceUnavailable)
        }
    }
    private func markRouteInterrupted(_ owner: RouteOwner, failure: DeviceServiceFailure) {
        if requestConnectionRecovery(failure: failure) { return }
        guard !owner.ended, movementAuthority.snapshot.lease == owner.intent.lease,
              movementAuthority.snapshot.runState == .running else { return }
        diagnose("route.interrupted", level: .notice, [
            "failure": .text(failure.rawValue),
            "pending": .count(owner.pendingCalls)
        ])
        owner.interrupted = true
        markSimulationPositionUnverified()
        movementAuthority.updateHealth(.interrupted(failure), for: owner.intent.lease)
        nativeBusy = outstandingWork > 0 || owner.pendingCalls > 0
        error = failure
        routeSubject.send(.interrupted(owner.intent.id, failure))
    }
    private func markRouteUnknown(_ owner: RouteOwner, failure: DeviceServiceFailure) {
        if requestConnectionRecovery(failure: failure) { return }
        guard !owner.ended else { return }
        diagnose("route.unknown", level: .notice, [
            "failure": .text(failure.rawValue),
            "pending": .count(owner.pendingCalls)
        ])
        owner.unknown = true; owner.unknownFailure = failure; routeUnconfirmed = true
        if movementAuthority.snapshot.lease == owner.intent.lease { movementAuthority.updateHealth(.unknown, for: owner.intent.lease) }
        else { movementAuthority.revokeAll() }
        phase = .repairRequired; error = failure
        nativeBusy = outstandingWork > 0 || owner.pendingCalls > 0
        routeSubject.send(.unknown(owner.intent.id, failure))
        quarantineJoystickOwners(failure)
    }
    private func quarantineCancelledRouteWrite(_ owner: RouteOwner, gate: PointDispatchGate, result: CommandResult) {
        guard owner.ended, owner.stopGeneration == routeStopGeneration else { return }
        let failure: DeviceServiceFailure
        switch result {
        case .point(.notSent(let value)) where gate.hasDispatched: failure = value
        case .point(.unconfirmed(let value)): failure = value
        case .point(.acknowledged) where !gate.hasDispatched: failure = .serviceUnavailable
        default: return
        }
        // Cancellation suppresses publication, but cannot turn an uncertain native write into a confirmed stop.
        owner.unknown = true; owner.unknownFailure = failure; routeUnconfirmed = true
        movementAuthority.revokeAll()
        phase = .repairRequired; error = failure
        routeSubject.send(.unknown(owner.intent.id, failure))
        quarantineJoystickOwners(failure)
    }
    private func resolveBegin(_ owner: RouteOwner, outcome: RouteCommandOutcome) {
        let continuation = owner.begin; owner.begin = nil
        continuation?.resume(returning: outcome)
    }
    private func idleSettlement(_ owner: RouteOwner) -> RouteIdleSettlement {
        if owner.stopGeneration == routeStopGeneration, owner.unknown {
            return .requiresStop(owner.unknownFailure ?? .serviceUnavailable)
        }
        return .settled
    }
    private func settle(_ owner: RouteOwner) {
        guard owner.pendingCalls == 0 else { return }
        if owner.ended { resolveBegin(owner, outcome: .cancelled) }
        let waiting = owner.idle; owner.idle = []
        for continuation in waiting { continuation.resume(returning: idleSettlement(owner)) }
        if owner.ended && (!owner.unknown || clearScheduled) { routeOwners.removeValue(forKey: owner.intent.id) }
    }
}

extension ServiceController {
    /// A wander or manual joystick that has begun but not ended. Its lease is
    /// installed by its first write, so until then the authority looks free.
    var hasLiveMovingJoystick: Bool {
        joystickOwners.values.contains { !$0.ended && $0.intent.fixedPosition == nil }
    }
    public var canBeginJoystick: Bool {
        let snapshot = movementAuthority.snapshot
        return canTeleport && (snapshot.lease == nil || snapshot.health == .confirmedHealthy)
            && joystickOwners.values.allSatisfy {
                $0.ended || $0.neutral || $0.paused ||
                    ($0.intent.fixedPosition != nil && $0.unknownFailure == nil)
            }
    }
    /// Execution admission accepts only a verified simulation coordinate or
    /// a fresh real fix. Retained simulation history remains display-only.
    /// The simulated position the device still holds: verified and not being
    /// cleared. Only Stop or Restore removes it.
    ///
    /// Display freshness is not consulted: leaving the foreground greys the
    /// arrow until a new ACK, but the device still holds this position.
    public var unclearedSimulatedCoordinate: GeoCoordinate? {
        guard deviceMayHoldSimulation, !clearScheduled, !coldClearPending,
              let position = lastDisplayedPosition, position.source == .simulation else { return nil }
        return position.coordinate
    }
    /// The position a paused task or an idle manual joystick still holds. No
    /// writer runs in these states, so a heartbeat resends it.
    var keepAliveTarget: (lease: MovementTaskLease, coordinate: GeoCoordinate)? {
        guard !nativeBusy, let coordinate = unclearedSimulatedCoordinate else { return nil }
        let snapshot = movementAuthority.snapshot
        guard let lease = snapshot.lease, snapshot.health == .confirmedHealthy else { return nil }
        if snapshot.runState == .paused { return (lease, coordinate) }
        let idleJoystick = joystickOwners.values.contains {
            $0.intent.lease == lease && !$0.ended && $0.neutral && $0.intent.fixedPosition == nil && $0.tick == nil
        }
        return idleJoystick ? (lease, coordinate) : nil
    }

    /// Resends the held position without changing the task, its lease or the
    /// displayed position. A dispatched write without an ACK greys the arrow;
    /// the next write decides about a repair.
    @discardableResult
    public func sendKeepAlive() async -> Bool {
        guard let target = keepAliveTarget else { return false }
        let gate = PointDispatchGate(keepingAlive: movementAuthority, lease: target.lease)
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ device in
                .point(await device.movePoint(to: target.coordinate, dispatch: gate))
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: false); return }
                let acknowledged: Bool
                if case .point(.acknowledged) = result { acknowledged = true } else { acknowledged = false }
                self.diagnose("keeper.heartbeat", level: acknowledged ? .debug : .notice, [
                    "result": .text(acknowledged ? "acked" : (gate.hasDispatched ? "unconfirmed" : "notSent"))
                ])
                if acknowledged, self.movementAuthority.snapshot.lease == target.lease {
                    // A real ACK of the held coordinate re-verifies the arrow.
                    self.publishSimulation(target.coordinate, displayEpoch: self.simulationDisplayEpoch)
                } else if gate.hasDispatched, self.movementAuthority.snapshot.lease == target.lease {
                    self.markSimulationPositionUnverified()
                }
                continuation.resume(returning: acknowledged)
            }
        }
    }

    /// A greyed (unverified) arrow is still where the device holds the
    /// location, so the joystick starts from it; its first ACK re-verifies.
    public var currentJoystickOrigin: GeoCoordinate? {
        if let marker = displayPositionMarker, marker.source == .simulation, marker.freshness == .fresh {
            return marker.coordinate
        }
        if let held = unclearedSimulatedCoordinate { return held }
        guard let realLocation, now().timeIntervalSince(realLocation.observedAt) <= 15 else { return nil }
        return realLocation.coordinate
    }
    public var movementAdmissionRevision: UInt64 { routeAdmissionRevision }
    public var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { joystickSubject.eraseToAnyPublisher() }
    public var movementAcknowledgements: AnyPublisher<MovementAcknowledgement, Never> {
        movementAcknowledgementSubject.eraseToAnyPublisher()
    }
    public var teleportAcknowledgements: AnyPublisher<TeleportAcknowledgement, Never> {
        teleportAcknowledgementSubject.eraseToAnyPublisher()
    }

    /// One-shot admission from a still-current explicit teleport ACK. Cold
    /// state, stale ACKs and newer user operations cannot start maintenance.
    public func beginPositionHold(after acknowledgement: TeleportAcknowledgement,
                                  intent: JoystickMovementIntent) async -> JoystickPreparationOutcome {
        guard movementAuthority.isSceneActive, !nativeBusy,
              simulationDisplayVerified, simulationDisplayEpoch == acknowledgement.displayEpoch,
              movementAdmissionRevision == acknowledgement.admissionRevision,
              movementAuthority.snapshot.lease == acknowledgement.lease,
              intent.fixedPosition == acknowledgement.coordinate,
              case .acknowledged(let point) = pointState,
              point.id == acknowledgement.intent.id else { return .cancelled }
        return await beginJoystick(intent, expectedMovementAdmissionRevision: acknowledgement.admissionRevision)
    }
    public func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome {
        guard canBeginJoystick, expectedMovementAdmissionRevision == movementAdmissionRevision,
              joystickOwners[intent.id] == nil else { return .cancelled }
        admitExplicitOperation()
        return await withCheckedContinuation { continuation in
            let owner = JoystickOwner(intent, stopGeneration: routeStopGeneration, begin: continuation)
            joystickOwners[intent.id] = owner
            beginPreparation(.joystick(intent))
        }
    }
    public func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              !owner.neutral, !owner.paused, owner.disposition == nil, owner.unknownFailure == nil,
              !joystickUnconfirmed, !routeUnconfirmed, !pointUnconfirmed else { return nil }
        return owner.inputRevision
    }
    private func resolveJoystickBeginning(_ owner: JoystickOwner, outcome: JoystickPreparationOutcome) {
        let continuation = owner.begin; owner.begin = nil
        continuation?.resume(returning: outcome)
    }

    private func cancelJoystickOwner(_ owner: JoystickOwner) {
        if !owner.ended {
            owner.ended = true
            owner.tick?.gate?.invalidate()
            movementAuthority.revoke(owner.intent.lease)
            joystickSubject.send(.ended(owner.intent.id))
        }
        settleJoystick(owner)
    }
    private func joystickSettlement(_ owner: JoystickOwner) -> JoystickIdleSettlement {
        if owner.stopGeneration == routeStopGeneration, let failure = owner.unknownFailure { return .requiresStop(failure) }
        return .settled
    }
    private func settleJoystick(_ owner: JoystickOwner) {
        guard owner.pendingCalls == 0 else { return }
        if owner.unknownFailure == nil, let disposition = owner.disposition {
            owner.disposition = nil
            switch disposition {
            case .endGesture:
                owner.ended = true
                movementAuthority.revoke(owner.intent.lease)
                joystickSubject.send(.ended(owner.intent.id))
            case .pause: owner.paused = true
            }
        }
        if owner.ended || owner.unknownFailure != nil { resolveJoystickBeginning(owner, outcome: .cancelled) }
        let waiting = owner.idle; owner.idle = []
        for continuation in waiting { continuation.resume(returning: joystickSettlement(owner)) }
        if owner.ended && (owner.unknownFailure == nil || clearScheduled) { joystickOwners.removeValue(forKey: owner.intent.id) }
        nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
    }

    public func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              !owner.neutral, !owner.paused, owner.disposition == nil, owner.unknownFailure == nil,
              !joystickUnconfirmed, !routeUnconfirmed, !pointUnconfirmed else { return nil }
        advanceJoystickInput(owner)
        return owner.inputRevision
    }
    private func advanceJoystickInput(_ owner: JoystickOwner) {
        owner.inputRevision = JoystickInputRevision(generation: owner.inputRevision.generation, revision: owner.inputRevision.revision &+ 1)
        if let tick = owner.tick, tick.gate == nil || tick.gate?.invalidateIfAvailable() == true {
            tick.inputCancelled = true
            tick.watchdog?.cancel()
        }
    }
    public func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                 expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome {
        switch await executeJoystickStep(executionID: executionID, lease: lease, sequence: sequence,
                                         expectedInputRevision: expectedInputRevision, recipe: .manual(displacement)) {
        case .acknowledged(let receipt): return .acknowledged(receipt.actualCoordinate)
        case .notSent(let failure): return .notSent(failure)
        case .unconfirmed(let failure): return .unconfirmed(failure)
        case .inputCancelled: return .inputCancelled
        case .cancelled: return .cancelled
        }
    }
    public func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                 expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome {
        await executeJoystickStep(executionID: executionID, lease: lease, sequence: sequence,
                                  expectedInputRevision: expectedInputRevision, recipe: recipe)
    }
    private func executeJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                     expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, owner.prepared,
              !owner.ended, !owner.neutral, !owner.paused, owner.disposition == nil,
              owner.unknownFailure == nil, owner.tick == nil, owner.stopGeneration == routeStopGeneration,
              movementAdmissionAllowed, owner.lastSequence < UInt64.max,
              sequence == owner.lastSequence + 1 else { return .cancelled }
        guard owner.inputRevision == expectedInputRevision else { return .inputCancelled }
        switch (owner.intent.fixedPosition, recipe) {
        case (.some(let allowed), .fixedPosition(let coordinate)) where allowed == coordinate:
            break
        case (.none, .manual), (.none, .target):
            break
        default:
            return .notSent(.device(.operationCancelled))
        }
        let tick = JoystickTick(sequence: sequence, input: expectedInputRevision,
            displayEpoch: simulationDisplayEpoch)
        owner.tick = tick; owner.pendingCalls += 1
        nativeBusy = true
        let tickStarted = DispatchTime.now().uptimeNanoseconds
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] service in
                guard let self, self.joystickTickIsCurrent(owner, tick), self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                guard !tick.inputCancelled, owner.inputRevision == tick.input else { tick.inputCancelled = true; return .failure(.operationCancelled) }
                let snapshot = self.movementAuthority.snapshot
                guard !self.clearScheduled, !self.pointUnconfirmed, !self.routeUnconfirmed, !self.joystickUnconfirmed,
                      snapshot.lease == nil || snapshot.health == .confirmedHealthy,
                      !owner.installed || self.movementAuthority.permitsDispatch(for: lease) else {
                    tick.failure = .device(.serviceUnavailable); return .failure(.operationCancelled)
                }
                guard let origin = self.currentJoystickOrigin else {
                    tick.failure = .originUnavailable; return .failure(.operationCancelled)
                }
                tick.origin = origin
                // No suspension between current truth, geometry, fresh CAS snapshot and gate construction.
                let receipt: JoystickStepReceipt
                switch recipe {
                case .manual(let displacement):
                    receipt = JoystickStepReceipt(actualCoordinate: JoystickGeodesy.destination(from: origin, displacement: displacement),
                        actualBearingDegrees: displacement.bearingDegrees, targetID: nil, arrived: false)
                case .target(let step):
                    let resolved = JoystickGeodesy.resolveTarget(from: origin, step: step)
                    receipt = JoystickStepReceipt(actualCoordinate: resolved.coordinate, actualBearingDegrees: resolved.bearingDegrees,
                        targetID: step.targetID, arrived: resolved.arrived)
                case .fixedPosition(let coordinate):
                    guard owner.intent.fixedPosition == coordinate, origin == coordinate else {
                        tick.failure = .device(.serviceUnavailable)
                        return .failure(.operationCancelled)
                    }
                    receipt = JoystickStepReceipt(actualCoordinate: coordinate,
                        actualBearingDegrees: nil, targetID: nil, arrived: false)
                }
                let fresh = self.movementAuthority.snapshot
                guard fresh.lease == nil || fresh.health == .confirmedHealthy else {
                    tick.failure = .device(.serviceUnavailable); return .failure(.operationCancelled)
                }
                tick.receipt = receipt
                let gate = PointDispatchGate(authority: self.movementAuthority, lease: lease,
                    replacing: owner.installed ? nil : fresh) { [weak self] in
                    Task { @MainActor in self?.joystickDidDispatch(executionID: executionID, sequence: sequence) }
                }
                tick.gate = gate
                tick.watchdog = Task { [weak self] in
                    guard let self else { return }
                    do { try await self.watchdogSleep(self.operationTimeout) } catch { return }
                    guard self.joystickTickIsCurrent(owner, tick), !tick.inputCancelled else { return }
                    tick.timedOut = true
                    self.diagnose("watchdog.fired", level: .error, [
                        "op": .text("joystick.tick"),
                        "seq": .count(Int(truncatingIfNeeded: sequence)),
                        "timeout_s": .number(Double(self.operationTimeout.components.seconds), digits: 0),
                        "dispatched": .flag(gate.hasDispatched)
                    ])
                    // Atomic invalidation wins against the native claim, or a
                    // pre-existing invalidation already prevented dispatch.
                    if gate.invalidateIfAvailable() || !gate.hasDispatched {
                        tick.failure = .device(.operationTimedOut)
                        self.error = .operationTimedOut
                        self.nativeBusy = true
                    } else if gate.hasDispatched {
                        self.joystickDidDispatch(owner, tick)
                        _ = self.unknownJoystick(owner, failure: .operationTimedOut)
                    }
                }
                return .point(await service.movePoint(to: receipt.actualCoordinate, dispatch: gate))
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: .cancelled); return }
                self.diagnoseResult("joystick.tick", result, op: "joystick",
                                    matched: true, outstanding: self.outstandingWork,
                                    extra: ["seq": .count(Int(truncatingIfNeeded: sequence)),
                                            "ms": .milliseconds(elapsedMilliseconds(since: tickStarted)),
                                            "dispatched": .flag(tick.gate?.hasDispatched == true)])
                let outcome = self.completeJoystickTick(owner, tick, result: result)
                tick.watchdog?.cancel()
                owner.tick = nil; owner.pendingCalls -= 1
                self.settleJoystick(owner)
                continuation.resume(returning: outcome)
                self.joystickSubject.send(.availabilityChanged)
            }
        }
    }
    private func joystickTickIsCurrent(_ owner: JoystickOwner, _ tick: JoystickTick) -> Bool {
        joystickOwners[owner.intent.id] === owner && owner.tick === tick && !owner.ended
            && owner.stopGeneration == routeStopGeneration
    }
    private func joystickDidDispatch(executionID: UUID, sequence: UInt64) {
        guard let owner = joystickOwners[executionID], let tick = owner.tick, tick.sequence == sequence else { return }
        joystickDidDispatch(owner, tick)
    }
    private func joystickDidDispatch(_ owner: JoystickOwner, _ tick: JoystickTick) {
        guard joystickTickIsCurrent(owner, tick), !clearScheduled, tick.gate?.hasDispatched == true,
              !tick.didInvalidateProof, movementAuthority.snapshot.lease == owner.intent.lease else { return }
        tick.didInvalidateProof = true
        invalidatePositionProof()
        endSupersededRoutes()
    }
    private func completeJoystickTick(_ owner: JoystickOwner, _ tick: JoystickTick, result: CommandResult) -> JoystickRecipeStepOutcome {
        guard joystickTickIsCurrent(owner, tick) else { return .cancelled }
        if tick.timedOut {
            if tick.gate?.hasDispatched == true { return .unconfirmed(.operationTimedOut) }
            return failJoystickBeforeClaim(owner, failure: .device(.operationTimedOut))
        }
        if let failure = owner.unknownFailure {
            return tick.gate?.hasDispatched == true ? .unconfirmed(failure) : .notSent(.device(failure))
        }
        // Even a withdrawn, unclaimed request cannot erase a malformed native
        // acknowledgement or an explicitly uncertain native result.
        if case .point(.unconfirmed(let failure)) = result { return unknownJoystick(owner, failure: failure) }
        if case .point(.acknowledged) = result, tick.gate?.hasDispatched != true {
            return unknownJoystick(owner, failure: .serviceUnavailable)
        }
        if tick.inputCancelled { return .inputCancelled }
        if tick.gate?.hasDispatched != true,
           pauseExpiredContinuation(movementID: owner.intent.id, lease: owner.intent.lease, result: result) {
            return .cancelled
        }
        if let failure = tick.failure { return failJoystickBeforeClaim(owner, failure: failure) }
        let outcome: PointDeliveryOutcome
        switch result {
        case .point(let value): outcome = value
        case .failure(let failure): outcome = .notSent(failure)
        case .success: outcome = .unconfirmed(.serviceUnavailable)
        }
        if tick.gate?.hasDispatched == true { joystickDidDispatch(owner, tick) }
        switch outcome {
        case .acknowledged where tick.gate?.hasDispatched == true:
            guard let receipt = tick.receipt, movementAuthority.snapshot.lease == owner.intent.lease else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            owner.installed = true; owner.lastSequence = tick.sequence
            movementAuthority.updateHealth(.confirmedHealthy, for: owner.intent.lease)
            publishSimulation(receipt.actualCoordinate, displayEpoch: tick.displayEpoch)
            guard let origin = tick.origin else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            let distance = JoystickGeodesy.distanceMeters(from: origin, to: receipt.actualCoordinate)
            guard distance.isFinite, distance >= 0 else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            movementAcknowledgementSubject.send(MovementAcknowledgement(
                movementID: owner.intent.id, lease: owner.intent.lease, sequence: tick.sequence,
                source: .joystick, acknowledgedDistanceMeters: distance,
                routePositionMeters: nil, finiteArrival: false))
            return .acknowledged(receipt)
        case .notSent(let failure) where tick.gate?.hasDispatched != true:
            return failJoystickBeforeClaim(owner, failure: .device(failure))
        case .notSent(let failure), .unconfirmed(let failure): return unknownJoystick(owner, failure: failure)
        case .acknowledged: return unknownJoystick(owner, failure: .serviceUnavailable)
        }
    }
    private func failJoystickBeforeClaim(_ owner: JoystickOwner, failure: JoystickFailure) -> JoystickRecipeStepOutcome {
        if case .device(let deviceFailure) = failure, requestConnectionRecovery(failure: deviceFailure) {
            return .notSent(failure)
        }
        owner.ended = true
        markSimulationPositionUnverified()
        movementAuthority.revoke(owner.intent.lease)
        joystickSubject.send(.interrupted(owner.intent.id, failure))
        return .notSent(failure)
    }
    private func unknownJoystick(_ owner: JoystickOwner, failure: DeviceServiceFailure) -> JoystickRecipeStepOutcome {
        if requestConnectionRecovery(failure: failure) { return .unconfirmed(failure) }
        guard owner.stopGeneration == routeStopGeneration else { return .cancelled }
        diagnose("joystick.unknown", level: .notice, [
            "failure": .text(failure.rawValue),
            "pending": .count(owner.pendingCalls),
            "installed": .flag(owner.installed)
        ])
        owner.unknownFailure = failure; joystickUnconfirmed = true
        if movementAuthority.snapshot.lease == owner.intent.lease { movementAuthority.updateHealth(.unknown, for: owner.intent.lease) }
        else { movementAuthority.revokeAll() }
        phase = .repairRequired; error = failure; nativeBusy = owner.pendingCalls > 0 || outstandingWork > 0
        joystickSubject.send(.unknown(owner.intent.id, failure))
        for route in Array(routeOwners.values) where route.begun && !route.ended && !route.unknown {
            markRouteUnknown(route, failure: failure)
        }
        quarantineJoystickOwners(failure)
        return .unconfirmed(failure)
    }
    private func quarantineJoystickOwners(_ failure: DeviceServiceFailure) {
        for owner in Array(joystickOwners.values) where !owner.ended && owner.unknownFailure == nil {
            owner.unknownFailure = failure; joystickUnconfirmed = true
            owner.tick?.gate?.invalidate()
            if let context = currentPreparation, case .joystick(let intent) = context.source, intent.id == owner.intent.id {
                context.dispatch.invalidate(); revision &+= 1; watchdog?.cancel()
                currentPreparation = nil; preparedOperation = nil
            }
            joystickSubject.send(.unknown(owner.intent.id, failure))
        }
    }
    @discardableResult public func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended, owner.unknownFailure == nil else { return false }
        if disposition == .pause {
            guard owner.installed, !owner.neutral, !owner.paused, owner.disposition == nil,
                  movementAuthority.snapshot.lease == lease,
                  movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        }
        advanceJoystickInput(owner)
        owner.disposition = disposition
        if disposition == .pause { movementAuthority.updateRunState(.paused, for: lease) }
        if let snapshot = preparedOperation, case .joystick(let intent) = snapshot.source, intent.id == executionID {
            _ = cancelPreparation(id: snapshot.id)
        }
        nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
        settleJoystick(owner)
        return true
    }
    public func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              owner.paused, owner.pendingCalls == 0, owner.unknownFailure == nil,
              !clearScheduled, !pointUnconfirmed, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.resumeForeground(lease) else { return false }
        rebuildConnectionForResume("joystick")
        owner.inputRevision = JoystickInputRevision()
        owner.paused = false; owner.neutral = true
        joystickSubject.send(.availabilityChanged)
        return true
    }
    public func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              owner.installed, owner.paused, owner.pendingCalls == 0, owner.tick == nil,
              owner.disposition == nil, owner.unknownFailure == nil, owner.stopGeneration == routeStopGeneration,
              !clearScheduled, !pointUnconfirmed, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.runState == .paused,
              movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.resumeForeground(lease) else { return false }
        rebuildConnectionForResume("joystickStream")
        owner.inputRevision = JoystickInputRevision()
        owner.paused = false; owner.neutral = false
        joystickSubject.send(.availabilityChanged)
        return true
    }
    /// A paused task's session may have been dropped by iOS while the app sat
    /// suspended, and its first write then failed as "resume failed". Every
    /// resume closes the old session first; the resumed owner's next write,
    /// queued behind this in the FIFO, opens a fresh one.
    private func rebuildConnectionForResume(_ op: String) {
        enqueueAdapter({ device in
            do { try await device.rebuildClientConnection(); return .success }
            catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
        }) { [weak self] result in
            guard let self else { return }
            self.diagnoseResult("resume.rebuild", result, op: op, matched: true, outstanding: self.outstandingWork)
        }
    }
    public func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease else { return .settled }
        guard owner.pendingCalls > 0 else { return joystickSettlement(owner) }
        return await withCheckedContinuation { owner.idle.append($0) }
    }

}

// MARK: - Diagnostics

private func elapsedMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
}

private extension ServiceController {
    private func diagnose(_ name: String, category: DiagnosticsCategory = .movement,
                  level: DiagnosticsLevel = .debug,
                  _ fields: [String: DiagnosticsField] = [:]) {
        Diagnostics.shared.record(name, category: category, level: level, fields)
    }

    /// Failures and uncertain writes are promoted to `.notice` so they survive
    /// in the device's persistent log; routine ticks stay at `.debug`.
    private func diagnoseResult(_ name: String, _ result: CommandResult, op: String,
                        matched: Bool, outstanding: Int, level: DiagnosticsLevel? = nil,
                        extra: [String: DiagnosticsField] = [:]) {
        var fields = extra
        fields["op"] = .text(op)
        fields["matched"] = .flag(matched)
        fields["outstanding"] = .count(outstanding)
        var eventLevel = level ?? .debug
        switch result {
        case .success:
            fields["result"] = .text("success")
        case .failure(let failure):
            fields["result"] = .text("failure")
            fields["failure"] = .text(failure.rawValue)
            eventLevel = .notice
        case .point(let outcome):
            switch outcome {
            case .acknowledged:
                fields["result"] = .text("acked")
            case .notSent(let failure):
                fields["result"] = .text("notSent")
                fields["failure"] = .text(failure.rawValue)
                eventLevel = .notice
            case .unconfirmed(let failure):
                fields["result"] = .text("unconfirmed")
                fields["failure"] = .text(failure.rawValue)
                eventLevel = .notice
            }
        }
        diagnose(name, level: eventLevel, fields)
        if name.hasSuffix(".tick") {
            completedTickCount &+= 1
            if completedTickCount % 20 == 0 {
                // A periodic persistent-log heartbeat: ticks themselves stay at
                // `.debug` in os_log, so a device log without an export still
                // shows that the 500 ms cadence was alive.
                diagnose("movement.heartbeat", level: .notice, [
                    "ticks": .count(Int(truncatingIfNeeded: completedTickCount)),
                    "phase": .text(phase.rawValue),
                    "busy": .flag(nativeBusy),
                    "op": .text(op)
                ])
            }
        }
    }
}
