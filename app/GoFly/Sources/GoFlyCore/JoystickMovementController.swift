import Combine
import Foundation

public enum JoystickMovementPhase: String, Equatable, Sendable {
    case neutral, preparing, moving, settling, pausing, paused, suspended, interrupted, unknown
}

@MainActor
public final class JoystickMovementController: ObservableObject {
    @Published public private(set) var phase: JoystickMovementPhase = .neutral
    @Published public private(set) var isRecoveringConnection = false
    @Published public private(set) var speed: RouteSpeed
    @Published public private(set) var input: JoystickInput?
    @Published public private(set) var activeGestureID: UUID?
    @Published public private(set) var intent: JoystickMovementIntent?
    @Published public private(set) var lastAcknowledgedCoordinate: GeoCoordinate?
    @Published public private(set) var lastAcknowledgedBearingDegrees: Double?
    @Published public private(set) var error: JoystickFailure?
    @Published public private(set) var wanderEnabled = false
    @Published public private(set) var wanderTarget: WanderTarget?
    @Published public private(set) var wanderRoute: PlannedRoute?
    @Published public private(set) var wanderProgressMeters: Double = 0
    @Published public private(set) var wanderNeedsReplan = false
    @Published public private(set) var wanderNeedsTarget = false
    @Published public private(set) var wanderError: WanderSelectionFailure?
    @Published public private(set) var suspensionReason: WanderSuspensionReason?
    public var displayInput: JoystickInput? {
        if let input { return input }
        guard wanderEnabled, hasAcknowledgedLease, let bearing = smoothedWanderBearingDegrees ?? lastAcknowledgedBearingDegrees else { return nil }
        return JoystickInput(bearingDegrees: bearing, strength: 1)
    }
    /// The road the map arrow may glide along between ACKs: none while a
    /// finger steers off it or a replacement road is still being planned.
    public var markerGlideRoute: PlannedRoute? {
        wanderEnabled && !wanderNeedsReplan && input == nil ? wanderRoute : nil
    }
    public var displayBearingDegrees: Double? { input?.bearingDegrees ?? smoothedWanderBearingDegrees ?? lastAcknowledgedBearingDegrees }
    /// Route tangent around the committed progress. Per-step bearings are chords
    /// from the live position and jump on jagged geometry; display uses this.
    public var smoothedWanderBearingDegrees: Double? {
        guard wanderEnabled, !wanderNeedsReplan, let route = wanderRoute,
              let a = route.coordinate(at: max(0, wanderProgressMeters - 3)),
              let b = route.coordinate(at: min(route.totalDistanceMeters, wanderProgressMeters + 3)), a != b else { return nil }
        return JoystickGeodesy.bearingDegrees(from: a, to: b)
    }
    /// Data-only history used by the recovery checkpoint. It never carries a
    /// native handle, input, lease, or authority proof.
    var recoveryWanderHistory: [GeoCoordinate] { wanderHistory }
    /// Recovery may describe manual movement only after this intent has
    /// received an actual native acknowledgement.
    var recoveryHasAcknowledgedLease: Bool { hasAcknowledgedLease }
    public var canBeginGesture: Bool {
        guard sceneActive, connectionAvailable else { return false }
        if wanderEnabled, activeGestureID == nil {
            // A probe may not interrupt an already-running manual override;
            // only the suspended wander-resume path is admission-gated.
            if phase == .preparing || phase == .moving { return true }
            if !recoveryProbePending, phase == .suspended && suspensionReason == .targetUnavailable { return true }
        }
        return phase == .neutral && commands.canBeginJoystick && !requiresOrigin
    }
    /// A wander segment ended and the next destination is being chosen. The wander is still
    /// running: this is neither a pause nor a stop, and must not surface as either.
    public var isAwaitingNextTarget: Bool {
        wanderEnabled && phase == .suspended && suspensionReason == .targetUnavailable
    }
    public var requiresOrigin: Bool { commands.currentJoystickOrigin == nil }
    public var requiresStop: Bool { phase == .unknown }
    public var canPause: Bool { isRecoveringConnection || (phase == .moving && hasAcknowledgedLease) }
    public var canResume: Bool {
        sceneActive && connectionAvailable && !recoveryProbePending && commands.canBeginJoystick &&
        (phase == .paused || (wanderEnabled && phase == .suspended && suspensionReason == .sceneInactive))
    }
    /// Recovery blocks a paused resume until its fresh probe settles without
    /// interrupting an already moving gesture.
    func recoveryProbeDidStart() { recoveryProbePending = true; objectWillChange.send() }
    func recoveryProbeDidFinish() { recoveryProbePending = false; objectWillChange.send() }
    public var canSetSpeed: Bool { [.neutral, .preparing, .moving, .paused, .suspended, .interrupted].contains(phase) }
    private var wanderHistory: [GeoCoordinate] = []
    private var wanderRouteRevision = UUID()
    private let wanderBearingSamples: @Sendable () -> [Double]
    /// The range automatic targets must stay in; nil leaves selection unbounded.
    public var wanderRange: @MainActor (GeoCoordinate) -> WanderRange? = { _ in nil }
    /// Called with the origin of each new automatic wander before its first target is picked.
    public var wanderStarting: @MainActor (GeoCoordinate) -> Void = { _ in }
    private var nextSequence: UInt64 = 1
    private var sceneActive = true
    private var connectionAvailable = true
    private var recoveryProbePending = false
    private let commands: any JoystickCommanding
    private let clock: any RouteClock
    private var task: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var generation: UInt64 = 0
    private var settlementRevision: UInt64 = 0
    private var hasAcknowledgedLease = false
    private var resumedNeutralIntent: JoystickMovementIntent?
    private var physicalOperations: Set<UUID> = []
    private let continuationControlSubject = PassthroughSubject<MovementContinuationControlEvent, Never>()
    private var continuationIdentity: MovementContinuationIdentity?

private func diagnose(_ name: String, category: DiagnosticsCategory, level: DiagnosticsLevel = .debug,
                      _ fields: [String: DiagnosticsField] = [:]) {
    Diagnostics.shared.record(name, category: category, level: level, fields)
}


    private func beginPhysicalOperation() -> UUID {
        let id = UUID(); physicalOperations.insert(id); return id
    }
    private func finishPhysicalOperation(_ id: UUID) { physicalOperations.remove(id) }


    public var continuationControlEvents: AnyPublisher<MovementContinuationControlEvent, Never> {
        continuationControlSubject.eraseToAnyPublisher()
    }

    public init(commands: any JoystickCommanding, clock: any RouteClock = ContinuousRouteClock(), speed: RouteSpeed = .standard,
                wanderBearingSamples: @escaping @Sendable () -> [Double] = { (0..<32).map { _ in Double.random(in: 0..<360) } }) {
        self.commands = commands; self.clock = clock; self.speed = speed; self.wanderBearingSamples = wanderBearingSamples
        subscription = commands.joystickEvents.sink { [weak self] event in self?.receive(event) }
    }

    @discardableResult public func beginGesture(id: UUID, input: JoystickInput) -> Bool {
        guard sceneActive, input.strength > 0 else { return false }
        if wanderEnabled, activeGestureID == nil, let intent, phase == .suspended, suspensionReason == .targetUnavailable {
            guard resumeWanderStream(intent) else { return false }
            _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
            activeGestureID = id; self.input = input
            return true
        }
        if wanderEnabled, activeGestureID == nil, let intent, phase == .preparing || phase == .moving {
            _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
            activeGestureID = id; self.input = input
            return true
        }
        guard canBeginGesture else { return false }
        return startMovement(gestureID: id, input: input)
    }

    private func startMovement(gestureID: UUID? = nil, input: JoystickInput? = nil) -> Bool {
        guard sceneActive, connectionAvailable, commands.canBeginJoystick, !requiresOrigin else { return false }
        generation &+= 1
        nextSequence = 1
        let token = generation, operation = JoystickMovementIntent(), admission = commands.movementAdmissionRevision
        intent = operation; activeGestureID = gestureID; self.input = input; error = nil
        hasAcknowledgedLease = false; phase = .preparing
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self, self.generation == token, self.phase == .preparing, !Task.isCancelled else { return }
            let outcome = await self.commands.beginJoystick(operation, expectedMovementAdmissionRevision: admission)
            guard self.generation == token, self.phase == .preparing, !Task.isCancelled else { return }
            diagnose("joystick.beginOutcome", category: .movement, level: .notice, [
                "prepared": .flag({ if case .prepared = outcome { return true } else { return false } }()),
                "wander": .flag(self.wanderEnabled)
            ])
            switch outcome {
            case .prepared:
                self.phase = .moving
                await self.run(operation, token: token)
            case .cancelled: self.returnToNeutral()
            }
        }
        return true
    }

    public var canSetWanderEnabled: Bool {
        (wanderEnabled || (sceneActive && connectionAvailable && [.neutral, .preparing, .moving, .paused].contains(phase) && !requiresOrigin &&
            (phase != .neutral || commands.canBeginJoystick) && (phase != .paused || !recoveryProbePending)))
    }
    /// Planner entry may use a bounded viewport origin even when no current
    /// location is available; execution remains gated until origin ACK.
    public var canStartWanderPlanning: Bool {
        sceneActive && connectionAvailable && !recoveryProbePending && !requiresStop
            && phase == .neutral && commands.canBeginJoystick
    }
    @discardableResult public func setWanderEnabled(_ enabled: Bool) -> Bool {
                guard enabled != wanderEnabled else { return true }
        if !enabled {
            let previousIdentity = continuationIdentity
            let manualContinues = input != nil
            clearWanderState()
            if let previousIdentity {
                continuationIdentity = nil
                continuationControlSubject.send(.withdrawn(previousIdentity, .automaticDisabled(manualInputContinues: manualContinues)))
            }
            if let intent { _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease) }
            if input == nil, let intent, phase != .unknown { settle(intent, disposition: .endGesture) }
            else if intent == nil, phase != .unknown { returnToNeutral() }
            return true
        }
        guard canSetWanderEnabled, let origin = commands.currentJoystickOrigin else { error = .originUnavailable; return false }
        let selected: WanderTarget
        if wanderRoute != nil, let wanderTarget { selected = wanderTarget }
        else {
            guard let automatic = selectTarget(origin: origin) else { wanderError = .noCandidate; return false }
            selected = automatic
        }
        wanderEnabled = true
        if wanderRoute == nil { commitTarget(selected) }
        if phase == .neutral {
            let started = startMovement()
            if started { requestContinuationIfEligible() }
            return started
        }
        if phase == .preparing || phase == .moving { requestContinuationIfEligible() }
        return true
    }
    public var canApplyWanderTarget: Bool {
        sceneActive && wanderEnabled && [.neutral, .preparing, .moving, .paused, .suspended].contains(phase)
    }
    public var canRandomizeWanderTarget: Bool { canApplyWanderTarget && !requiresOrigin }
    @discardableResult public func applyWanderTarget(_ place: MapPlace) -> Bool {
        guard canApplyWanderTarget else { return false }
        commitTarget(WanderTarget(place: place))
        return true
    }
    @discardableResult public func randomizeWanderTarget() -> Bool {
        guard canRandomizeWanderTarget, let origin = commands.currentJoystickOrigin else { return false }
        guard let selected = selectTarget(origin: origin) else { wanderError = .noCandidate; return false }
        commitTarget(selected)
        return true
    }
    public func clearWanderError() { wanderError = nil }
    public func setWanderPlanningFailed() { wanderError = .planningFailed }
    public func markWanderNeedsReplan() { if wanderEnabled, wanderRoute != nil { wanderNeedsReplan = true } }
    public func selectWanderTarget(from origin: GeoCoordinate) -> WanderTarget? { selectTarget(origin: origin) }

    /// Installs a fully validated road segment for the existing joystick
    /// owner. The road entrance must be continuous with the current confirmed
    /// origin; no synthetic connector is inserted.
    @discardableResult public func installWanderRoute(target: WanderTarget, route: PlannedRoute) -> Bool {
        guard !wanderEnabled, let origin = commands.currentJoystickOrigin,
              JoystickGeodesy.distanceMeters(from: origin, to: route.start) <= 1 else { return false }
        commitTarget(target)
        wanderRouteRevision = UUID()
        wanderRoute = route
        wanderProgressMeters = 0
        wanderNeedsReplan = false
        return true
    }

    public func pauseForWanderReplan() async -> Bool {
        guard wanderEnabled, hasAcknowledgedLease, intent != nil, !requiresStop else { return false }
        if phase == .moving {
            guard pause() else { return false }
            await transition?.value
        }
        return phase == .paused && intent != nil && !requiresStop
    }

    @discardableResult public func replaceWanderRouteAndResume(target: WanderTarget, route: PlannedRoute) -> Bool {
        guard sceneActive, wanderEnabled, phase == .paused, hasAcknowledgedLease, let intent,
              let origin = commands.currentJoystickOrigin,
              JoystickGeodesy.distanceMeters(from: origin, to: route.start) <= 1 else { return false }
        return resumeWanderStream(intent) { [weak self] in
            guard let self else { return }
            self.commitTarget(target)
            self.wanderRouteRevision = UUID()
            self.wanderRoute = route
            self.wanderProgressMeters = 0
            self.wanderNeedsTarget = false
            self.wanderNeedsReplan = false
        }
    }

    /// Replaces a completed segment while retaining its paused movement lease.
    /// The origin must still be the last acknowledged endpoint.
    @discardableResult public func installNextWanderRouteAndResume(target: WanderTarget, route: PlannedRoute) -> Bool {
        guard sceneActive, wanderEnabled, phase == .suspended, suspensionReason == .targetUnavailable,
              hasAcknowledgedLease, let intent,
              let origin = commands.currentJoystickOrigin,
              JoystickGeodesy.distanceMeters(from: origin, to: route.start) <= 1 else { return false }
        return resumeWanderStream(intent) { [weak self] in
            guard let self else { return }
            self.commitTarget(target)
            self.wanderRouteRevision = UUID()
            self.wanderRoute = route
            self.wanderProgressMeters = 0
            self.wanderNeedsTarget = false
            self.wanderNeedsReplan = false
        }
    }

    public var canRetryWander: Bool {
        sceneActive && connectionAvailable && !recoveryProbePending && wanderEnabled && !requiresOrigin && (phase == .neutral || (phase == .suspended && suspensionReason == .targetUnavailable))
    }
    @discardableResult public func retryWander() -> Bool {
        guard canRetryWander else { return false }
        if phase == .neutral {
            let started = startMovement()
            if started { requestContinuationIfEligible() }
            return started
        }
        guard let intent else { return false }
        let selected: WanderTarget?
        if wanderNeedsTarget {
            guard let origin = commands.currentJoystickOrigin, let candidate = selectTarget(origin: origin) else { wanderError = .noCandidate; return false }
            selected = candidate
        } else { selected = nil }
        return resumeWanderStream(intent, selected: selected)
    }
    private func resumeWanderStream(_ operation: JoystickMovementIntent, selected: WanderTarget? = nil,
                                    beforeStart: (@MainActor () -> Void)? = nil) -> Bool {
        guard sceneActive, connectionAvailable, !recoveryProbePending else { return false }
        guard commands.resumeJoystickStream(executionID: operation.id, lease: operation.lease) else { error = .device(.serviceUnavailable); return false }
        if let selected { commitTarget(selected) }
        beforeStart?()
        generation &+= 1
        let token = generation
        phase = .moving; suspensionReason = nil; input = nil; activeGestureID = nil; error = nil
        requestContinuationIfEligible()
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            await self?.run(operation, token: token)
        }
        return true
    }
    private func suspendForUnavailableTarget() {
        guard let intent, hasAcknowledgedLease,
              commands.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause) else {
            markUnknown(.serviceUnavailable); return
        }
        settle(intent, disposition: .pause, alreadyReleased: true, finalPhase: .suspended, reason: .targetUnavailable)
    }
    private func advanceTarget(from coordinate: GeoCoordinate) {
        if let selected = selectTarget(origin: coordinate) { commitTarget(selected) }
        else {
            wanderNeedsTarget = true; wanderError = .noCandidate
            if input == nil, phase == .moving { suspendForUnavailableTarget() }
        }
    }

    private func selectTarget(origin: GeoCoordinate) -> WanderTarget? {
        WanderTargetSelector.select(origin: origin, speed: speed,
            bearingSamples: wanderBearingSamples(), range: wanderRange(origin))
    }
    private func commitTarget(_ target: WanderTarget) {
        if let intent { _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease) }
        wanderTarget = target; wanderNeedsTarget = false; wanderError = nil
        wanderHistory.append(target.coordinate)
        if wanderHistory.count > 100 { wanderHistory.removeFirst(wanderHistory.count - 100) }
    }
    private func clearWanderState() {
        wanderEnabled = false; wanderTarget = nil; wanderNeedsTarget = false; wanderError = nil
        wanderHistory = []; suspensionReason = nil; wanderRoute = nil; wanderProgressMeters = 0
        wanderNeedsReplan = false
        wanderRouteRevision = UUID()
    }

    @discardableResult public func updateGesture(id: UUID, input: JoystickInput) -> Bool {
        guard activeGestureID == id, let intent, phase == .preparing || phase == .moving else { return false }
        var input = input
        if input.strength <= 0 {
            // Passing the centre does not hand a wander back to the road: the
            // finger still owns movement, holds still, and keeps its bearing.
            guard wanderEnabled, let held = JoystickInput(bearingDegrees: self.input?.bearingDegrees ?? input.bearingDegrees,
                                                          strength: 0) else { return endGesture(id: id) }
            input = held
        }
        guard self.input != input else { return true }
        _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
        self.input = input
        return true
    }
    @discardableResult public func setSpeed(_ speed: RouteSpeed) -> Bool {
        guard canSetSpeed else { return false }
        guard self.speed != speed else { return true }
        if (input != nil || wanderEnabled), let intent { _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease) }
        self.speed = speed
        return true
    }

    @discardableResult public func endGesture(id: UUID) -> Bool {
        if isRecoveringConnection, activeGestureID == id {
            input = nil; activeGestureID = nil
            if !wanderEnabled { _ = pause() }
            return true
        }
        guard activeGestureID == id, let intent, phase == .preparing || phase == .moving else { return false }
        if wanderEnabled {
            _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
            input = nil; activeGestureID = nil
            if wanderRoute != nil, wanderTarget != nil { wanderNeedsReplan = true }
            if wanderNeedsTarget { suspendForUnavailableTarget() }
        } else { settle(intent, disposition: .endGesture) }
        return true
    }

    func suspendForConnectionRecovery() -> Bool {
        if isRecoveringConnection { return true }
        guard phase == .moving, hasAcknowledgedLease else { return false }
        isRecoveringConnection = true
        generation &+= 1
        task?.cancel()
        phase = .paused
        return true
    }

    func finishConnectionRecovery(succeeded: Bool) {
        guard isRecoveringConnection, let intent else { return }
        isRecoveringConnection = false
        guard succeeded else {
            phase = .interrupted; error = .device(.serviceUnavailable)
            withdrawContinuation(.ended)
            return
        }
        error = nil
        if !wanderEnabled, activeGestureID == nil { phase = .neutral; return }
        phase = .moving
        let token = generation
        task = Task { [weak self] in await self?.run(intent, token: token) }
    }

    @discardableResult public func pause() -> Bool {
        if isRecoveringConnection {
            isRecoveringConnection = false
            commands.cancelConnectionRecovery()
            withdrawContinuation(.userPaused)
            input = nil; activeGestureID = nil; phase = .paused
            return true
        }
        guard canPause, let intent,
              commands.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause) else { return false }
        withdrawContinuation(.userPaused)
        settle(intent, disposition: .pause, alreadyReleased: true)
        return true
    }
    @discardableResult public func resume() -> Bool {
        guard canResume else { return false }
        if wanderEnabled, phase == .suspended, suspensionReason == .sceneInactive {
            guard commands.canBeginJoystick, !requiresOrigin else { error = .originUnavailable; return false }
            suspensionReason = nil
            let started = startMovement()
            if started { requestContinuationIfEligible() }
            return started
        }
        guard let intent else { return false }
        if wanderEnabled {
            if wanderNeedsTarget {
                guard let origin = commands.currentJoystickOrigin, let selected = selectTarget(origin: origin) else { wanderError = .noCandidate; return false }
                return resumeWanderStream(intent, selected: selected)
            }
            return resumeWanderStream(intent)
        }
        guard commands.resumeJoystick(executionID: intent.id, lease: intent.lease) else { return false }
        generation &+= 1
        resumedNeutralIntent = intent
        phase = .neutral; input = nil; activeGestureID = nil
        return true
    }
    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        if isRecoveringConnection, continuingLease != intent?.lease { _ = pause() }
        sceneActive = false
        if let intent, continuingLease == intent.lease, wanderEnabled, hasAcknowledgedLease, phase == .moving {
            input = nil
            activeGestureID = nil
            _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
            objectWillChange.send()
            return
        }
        releaseForUnavailable(reason: .sceneInactive)
    }

    public func sceneDidBecomeActive() { sceneActive = true; objectWillChange.send() }

    public func connectionDidBecomeUnavailable() {
        connectionAvailable = false
        releaseForUnavailable(reason: .connectionUnavailable)
    }

    public func connectionDidBecomeAvailable() {
        connectionAvailable = true
        objectWillChange.send()
    }

    public func continuationDidBecomeUnavailable() {
        if isRecoveringConnection { _ = pause() }
                releaseForUnavailable(reason: .backgroundUnavailable)
    }

    private func releaseForUnavailable(reason: WanderSuspensionReason) {
        diagnose("joystick.suspended", category: .movement, level: .notice, [
            "reason": .text(reason.rawValue),
            "phase": .text(phase.rawValue),
            "wander": .flag(wanderEnabled),
            "acknowledged": .flag(hasAcknowledgedLease)
        ])
        // A new preclaim gesture has not replaced the resumed healthy owner yet.
        if let neutral = resumedNeutralIntent, neutral.id != intent?.id {
            if commands.releaseJoystick(executionID: neutral.id, lease: neutral.lease, disposition: .endGesture) {
                resumedNeutralIntent = nil
            }
        }
        if wanderEnabled {
            if phase == .paused || phase == .suspended || phase == .pausing || phase == .unknown { return }
            guard let intent else { phase = .suspended; suspensionReason = reason; return }
            if hasAcknowledgedLease {
                guard commands.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause) else { markUnknown(.serviceUnavailable); return }
                settle(intent, disposition: .pause, alreadyReleased: true,
                    finalPhase: wanderNeedsTarget ? .suspended : .paused,
                    reason: wanderNeedsTarget ? .targetUnavailable : reason)
            } else {
                settle(intent, disposition: .endGesture, finalPhase: .suspended, reason: reason)
            }
            return
        }
        guard let intent, phase != .unknown, phase != .settling else { return }
        settle(intent, disposition: .endGesture)
    }
    public func clearError() { if !requiresStop { error = nil } }

    private func settle(_ operation: JoystickMovementIntent, disposition: JoystickReleaseDisposition, alreadyReleased: Bool = false,
                        finalPhase: JoystickMovementPhase? = nil, reason: WanderSuspensionReason? = nil) {
        input = nil; activeGestureID = nil
        phase = disposition == .pause ? .pausing : .settling
        settlementRevision &+= 1
        let settlementToken = settlementRevision
        let token = generation, running = task
        running?.cancel()
        if !alreadyReleased { commands.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: disposition) }
        let physicalID = beginPhysicalOperation()
        transition = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self else { return }
            let settlement = await self.commands.waitForJoystickIdle(executionID: operation.id, lease: operation.lease)
            await running?.value
            guard self.generation == token, self.settlementRevision == settlementToken, self.intent?.id == operation.id else { return }
            switch settlement {
            case .requiresStop(let failure): self.markUnknown(failure)
            case .settled:
                guard self.phase != .unknown else { return }
                if disposition == .pause { self.phase = finalPhase ?? .paused; self.suspensionReason = reason }
                else {
                    self.returnToNeutral()
                    if let finalPhase { self.phase = finalPhase; self.suspensionReason = reason }
                }
            }
        }
    }

    private func run(_ operation: JoystickMovementIntent, token: UInt64) async {
        while generation == token, phase == .moving, !Task.isCancelled {
            // A finger on the joystick keeps the manual cadence, including
            // during a wander override; road wander alone uses the path cadence.
            let manual = input != nil || !wanderEnabled
            let seconds = manual ? MovementCadence.manualSeconds : MovementCadence.pathSeconds
            do { try await clock.sleep(for: manual ? MovementCadence.manual : MovementCadence.path) } catch { return }
            guard generation == token, phase == .moving, !Task.isCancelled,
                  let revision = commands.joystickInputRevision(executionID: operation.id, lease: operation.lease) else {
                diagnose("joystick.runEnded", category: .movement, level: .notice, [
                    "why": .text(generation != token ? "generation" : phase != .moving ? "phase.\(phase.rawValue)" : Task.isCancelled ? "cancelled" : "noInputRevision"),
                    "wander": .flag(wanderEnabled)
                ])
                return
            }
            if wanderNeedsReplan, input == nil {
                diagnose("joystick.runEnded", category: .movement, level: .notice, ["why": .text("needsReplan")])
                return
            }
            guard nextSequence < UInt64.max else {
                continuationDidBecomeUnavailable()
                return
            }
            let recipe: JoystickStepRecipe
            var capturedRouteRevision: UUID? = nil
            var routeStepDistance: Double? = nil
            if let input {
                // A wander finger resting at the centre: no write, and no road step either.
                guard let displacement = input.displacement(speed: speed, seconds: seconds) else { continue }
                recipe = .manual(displacement)
            }
            else if wanderEnabled, !wanderNeedsTarget, let route = wanderRoute, let target = wanderTarget,
                    let distance = nextRouteStepDistance(route: route, speed: speed, seconds: seconds),
                    let coordinate = route.coordinate(at: distance),
                    let step = JoystickTargetStep(targetID: target.id, coordinate: coordinate,
                        maximumDistanceMeters: speed.metersPerSecond * seconds) {
                recipe = .target(step); capturedRouteRevision = wanderRouteRevision; routeStepDistance = distance
            }
            else if wanderEnabled, !wanderNeedsTarget, let target = wanderTarget,
                    let step = JoystickTargetStep(targetID: target.id, coordinate: target.coordinate,
                        maximumDistanceMeters: speed.metersPerSecond * seconds) {
                recipe = .target(step); capturedRouteRevision = nil; routeStepDistance = nil
            }
            else {
                diagnose("joystick.runEnded", category: .movement, level: .notice, [
                    "why": .text("noRecipe"), "wander": .flag(wanderEnabled),
                    "needsTarget": .flag(wanderNeedsTarget), "hasRoute": .flag(wanderRoute != nil),
                    "hasTarget": .flag(wanderTarget != nil)
                ])
                return
            }
            let capturedTargetID = wanderTarget?.id, capturedNeedsTarget = wanderNeedsTarget
            let outcome = await commands.sendJoystickStep(executionID: operation.id, lease: operation.lease,
                sequence: nextSequence, expectedInputRevision: revision, recipe: recipe)
            guard generation == token, intent?.id == operation.id, phase != .unknown else { return }
            switch outcome {
            case .acknowledged(let receipt):
                nextSequence += 1
                lastAcknowledgedCoordinate = receipt.actualCoordinate
                if let bearing = receipt.actualBearingDegrees { lastAcknowledgedBearingDegrees = bearing }
                hasAcknowledgedLease = true
                if let capturedRouteRevision, capturedRouteRevision == wanderRouteRevision,
                   let routeStepDistance, receipt.arrived {
                    wanderProgressMeters = max(wanderProgressMeters, routeStepDistance)
                    if let route = wanderRoute, wanderProgressMeters >= route.totalDistanceMeters - 0.5 {
                        wanderNeedsTarget = true
                        if input == nil { suspendForUnavailableTarget() }
                    }
                }
                if wanderEnabled, !capturedNeedsTarget, let target = wanderTarget, target.id == capturedTargetID {
                    let arrived: Bool
                    switch recipe {
                    case .manual: arrived = JoystickGeodesy.distanceMeters(from: receipt.actualCoordinate, to: target.coordinate) <= 1
                    case .target: arrived = capturedRouteRevision == nil && receipt.targetID == target.id && receipt.arrived
                    case .fixedPosition: arrived = false
                    }
                    if arrived { advanceTarget(from: receipt.actualCoordinate) }
                }
            case .inputCancelled: break
            case .cancelled:
                withdrawContinuation(.ended)
                if phase == .moving { returnToNeutral() }
                return
            case .notSent(let failure):
                diagnose("joystick.stepFailed", category: .movement, level: .notice, [
                    "seq": .count(Int(truncatingIfNeeded: nextSequence)),
                    "failure": .text(failure.localizationKey),
                    "wander": .flag(wanderEnabled)
                ])
                withdrawContinuation(.ended)
                error = failure
                commands.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: .endGesture)
                returnToNeutral()
                return
            case .unconfirmed(let failure):
                diagnose("joystick.stepUnknown", category: .movement, level: .notice, [
                    "seq": .count(Int(truncatingIfNeeded: nextSequence)),
                    "failure": .text(failure.rawValue),
                    "wander": .flag(wanderEnabled)
                ])
                markUnknown(failure); return
            }
        }
    }

    private func nextRouteStepDistance(route: PlannedRoute, speed: RouteSpeed, seconds: Double) -> Double? {
        guard route.totalDistanceMeters.isFinite, route.totalDistanceMeters > 0,
              wanderProgressMeters.isFinite, wanderProgressMeters >= 0 else { return nil }
        return min(route.totalDistanceMeters, wanderProgressMeters + speed.metersPerSecond * seconds)
    }

    private func markUnknown(_ failure: DeviceServiceFailure) {
        phase = .unknown; error = .device(failure); input = nil; activeGestureID = nil
        task?.cancel()
    }
    private func returnToNeutral() {
        if resumedNeutralIntent?.id == intent?.id { resumedNeutralIntent = nil }
        phase = .neutral; input = nil; activeGestureID = nil; intent = nil; hasAcknowledgedLease = false
    }

    private func requestContinuationIfEligible() {
        guard sceneActive, wanderEnabled, let intent,
              phase == .preparing || phase == .moving else { return }
        diagnose("background.requested", category: .background, level: .notice, [
            "kind": .text("wander"),
            "movement": .text(intent.id.uuidString)
        ])
        continuationIdentity = MovementContinuationIdentity(movementID: intent.id, lease: intent.lease)
        continuationControlSubject.send(.requested(MovementContinuationDemand(
            movementID: intent.id, lease: intent.lease, kind: .wander,
            goal: .finiteDuration(seconds: BackgroundRunDuration.shared.seconds))))
    }

    private func withdrawContinuation(_ reason: MovementContinuationWithdrawalReason) {
        guard let identity = continuationIdentity else { return }
        diagnose("background.withdrawn", category: .background, level: .notice, [
            "reason": .text(reason.diagnosticsLabel),
            "movement": .text(identity.movementID.uuidString),
            "phase": .text(phase.rawValue)
        ])
        continuationIdentity = nil
        continuationControlSubject.send(.withdrawn(identity, reason))
    }

    private func receive(_ event: JoystickCommandEvent) {
        switch event {
        case .availabilityChanged: objectWillChange.send()
        case .movementBoundary(let lease):
            if let lease, lease == intent?.lease { return }
            generation &+= 1; settlementRevision &+= 1
            task?.cancel(); transition?.cancel()
            clearWanderState(); error = nil; resumedNeutralIntent = nil
            returnToNeutral()
        case .ended(let id):
            if intent?.id == id { isRecoveringConnection = false }
            if resumedNeutralIntent?.id == id { resumedNeutralIntent = nil }
            guard intent?.id == id else { return }
            withdrawContinuation(.ended)
            // Release waits for its actual call to return before accepting another gesture.
            guard phase != .settling && phase != .pausing else { return }
            generation &+= 1; task?.cancel(); returnToNeutral()
        case .unknown(let id, let failure):
            guard intent?.id == id else { return }
            withdrawContinuation(.ended)
            markUnknown(failure)
        case .interrupted(let id, let failure):
            guard intent?.id == id, phase != .unknown else { return }
            phase = .interrupted; error = failure; input = nil; activeGestureID = nil; task?.cancel()
        }
    }

    deinit { task?.cancel(); transition?.cancel() }
}
