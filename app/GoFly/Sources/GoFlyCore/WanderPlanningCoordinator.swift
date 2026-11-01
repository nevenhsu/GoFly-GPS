import Combine
import Foundation

/// Screen state wander planning reads and the effects it hands back. The map
/// screen attaches one on appear; until then planning sees an inactive scene.
@MainActor
public struct WanderPlanningHost {
    public var isJoystickMode: @MainActor () -> Bool
    public var isSceneActive: @MainActor () -> Bool
    public var isRecoveryChecking: @MainActor () -> Bool
    /// Fallback planning origins near the visible map when no origin is known.
    public var mapOriginCandidates: @MainActor () -> [GeoCoordinate]
    public var wanderStarted: @MainActor (PlannedRoute) -> Void
    public var segmentReplaced: @MainActor (PlannedRoute) -> Void
    public var destinationCleared: @MainActor () -> Void

    public init(isJoystickMode: @escaping @MainActor () -> Bool,
                isSceneActive: @escaping @MainActor () -> Bool,
                isRecoveryChecking: @escaping @MainActor () -> Bool,
                mapOriginCandidates: @escaping @MainActor () -> [GeoCoordinate],
                wanderStarted: @escaping @MainActor (PlannedRoute) -> Void = { _ in },
                segmentReplaced: @escaping @MainActor (PlannedRoute) -> Void = { _ in },
                destinationCleared: @escaping @MainActor () -> Void = {}) {
        self.isJoystickMode = isJoystickMode; self.isSceneActive = isSceneActive
        self.isRecoveryChecking = isRecoveryChecking; self.mapOriginCandidates = mapOriginCandidates
        self.wanderStarted = wanderStarted; self.segmentReplaced = segmentReplaced
        self.destinationCleared = destinationCleared
    }

    static let detached = WanderPlanningHost(
        isJoystickMode: { false }, isSceneActive: { false }, isRecoveryChecking: { false },
        mapOriginCandidates: { [] })
}

/// Plans road segments for wander and hands them to the joystick movement
/// owner. Startup, replacement and continuation planning each carry an ID so a
/// stale or failed planner result can never start or change a wander.
@MainActor
public final class WanderPlanningCoordinator: ObservableObject {
    public typealias SegmentPlanner = @MainActor (GeoCoordinate, GeoCoordinate) async throws -> PlannedRoute

    struct PendingStart {
        let plannerID: UUID
        let target: WanderTarget
        let route: PlannedRoute
        let teleportIntentID: UUID
        var originAcknowledged = false
    }

    struct Checkpoint {
        enum Purpose { case startup, replacement, continuation }
        let purpose: Purpose
        let origin: GeoCoordinate?
        let target: WanderTarget?
    }

    /// A running wander is replacing or continuing its road segment.
    @Published public private(set) var isReplanning = false
    /// The destination a failed replacement retries.
    private var retryDestination: MapPlace?

    private let service: ServiceController
    private let joystick: JoystickMovementController
    private let joystickOrigin: JoystickOriginController
    private let planSegment: SegmentPlanner
    private var host = WanderPlanningHost.detached

    /// A start was requested and has not become a running wander yet: planning,
    /// the origin teleport, or its deferred hand-off.
    @Published public private(set) var isStarting = false
    private func refreshStarting() {
        // A pending start whose origin request was cancelled will never be
        // acknowledged, so it must not keep the Start button busy.
        let starting = planningTask != nil || (pendingStart != nil && joystickOrigin.request.isSetting)
        if isStarting != starting { isStarting = starting }
    }

    private var planningTask: Task<Void, Never>? {
        didSet { refreshStarting() }
    }
    private var planningID: UUID?
    private var replanningTask: Task<Void, Never>? {
        didSet { if isReplanning != (replanningTask != nil) { isReplanning = replanningTask != nil } }
    }
    private var replanningID: UUID?
    private var activeCheckpoint: Checkpoint?
    private var interruptedCheckpoint: Checkpoint?
    private var pendingStart: PendingStart? {
        didSet { refreshStarting() }
    }
    private var deferredStart = WanderStartRequestGate()

    public init(service: ServiceController, joystick: JoystickMovementController,
                origin: JoystickOriginController, planSegment: @escaping SegmentPlanner) {
        self.service = service; self.joystick = joystick; self.joystickOrigin = origin
        self.planSegment = planSegment
        originSubscription = origin.$request.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStarting() }
    }
    private var originSubscription: AnyCancellable?

    public func attach(_ host: WanderPlanningHost) { self.host = host }

    public var canRequestStart: Bool {
        let origin = joystickOrigin.request
        return joystick.canStartWanderPlanning || (origin.isSetting && origin.intentID != nil
            && host.isJoystickMode() && !joystick.wanderEnabled && !joystick.requiresStop)
    }
    /// The start teleport was acknowledged but the wander waits for native work to drain.
    public var hasAcknowledgedPendingStart: Bool { pendingStart?.originAcknowledged == true }
    /// The teleport intent is the automatic origin of a wander start.
    public func isStartOrigin(_ intentID: UUID) -> Bool { pendingStart?.teleportIntentID == intentID }

    // MARK: Startup

    /// Plans a road segment before enabling the existing joystick movement
    /// owner. A stale or failed planner result cannot start a wander task.
    public func start(preselectedOrigin: GeoCoordinate? = nil, preselectedTarget: WanderTarget? = nil) {
        // Automatic wander only starts after a real connection success.
        guard service.movementConnection == .available else { return }
        guard host.isJoystickMode(), !joystick.wanderEnabled, canRequestStart else { return }
        guard pendingStart == nil else { return }
        let originRequest = joystickOrigin.request
        if originRequest.isSetting, let originIntentID = originRequest.intentID {
            deferredStart.waitForOriginAcknowledgement(originIntentID)
            return
        }
        if originRequest.isSetting { joystickOrigin.cancel() }
        planningTask?.cancel()
        let planningID = UUID()
        self.planningID = planningID
        interruptedCheckpoint = nil
        activeCheckpoint = Checkpoint(purpose: .startup, origin: preselectedOrigin, target: preselectedTarget)
        joystick.clearWanderError()
        let confirmedOrigin = preselectedOrigin ?? service.currentJoystickOrigin
        let originCandidates = originCandidates(preferred: confirmedOrigin)
        planningTask = Task { @MainActor in
            defer {
                if self.planningID == planningID {
                    planningTask = nil
                    if pendingStart?.plannerID != planningID { self.planningID = nil }
                }
            }
            for originCandidate in originCandidates.prefix(3) {
                guard !Task.isCancelled, self.planningID == planningID, host.isJoystickMode(),
                      !joystick.wanderEnabled else { return }
                let origin = service.currentJoystickOrigin ?? originCandidate
                guard let target = preselectedTarget ?? joystick.selectWanderTarget(from: origin) else { continue }
                activeCheckpoint = Checkpoint(purpose: .startup, origin: origin, target: target)
                do {
                    let planned = try await planSegment(origin, target.coordinate)
                    guard !Task.isCancelled, self.planningID == planningID, host.isJoystickMode(),
                          !joystick.wanderEnabled else { return }
                    if let currentOrigin = service.currentJoystickOrigin,
                       JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) > 1 { continue }
                    let hasLiveSimulation = service.displayPositionMarker?.source == .simulation
                        && service.displayPositionMarker?.freshness == .fresh
                    if hasLiveSimulation, let liveOrigin = service.currentJoystickOrigin,
                       JoystickGeodesy.distanceMeters(from: liveOrigin, to: planned.start) > 1 { continue }
                    if hasLiveSimulation {
                        installAndStart(target: target, route: planned, plannerID: planningID)
                    } else {
                        guard joystickOrigin.request.isSetting == false,
                              service.teleport(to: TeleportCandidate(place: MapPlace(
                                id: .coordinate(planned.start), title: planned.start.displayText,
                                coordinate: planned.start))),
                              case .preparing(let intent) = service.pointState else {
                            failPlanning(planningID); return
                        }
                        joystickOrigin.request = JoystickOriginRequest(isSetting: true, intentID: intent.id)
                        pendingStart = PendingStart(plannerID: planningID,
                            target: target, route: planned, teleportIntentID: intent.id)
                        activeCheckpoint = nil
                    }
                    return
                } catch is CancellationError { return }
                catch {
                    if service.movementConnection == .unavailable { return }
                    continue
                }
            }
            guard !Task.isCancelled, self.planningID == planningID else { return }
            failPlanning(planningID)
        }
    }

    private func originCandidates(preferred: GeoCoordinate?) -> [GeoCoordinate] {
        if let preferred { return [preferred, preferred, preferred] }
        return host.mapOriginCandidates()
    }

    @discardableResult private func installAndStart(target: WanderTarget, route planned: PlannedRoute, plannerID: UUID) -> Bool {
        guard planningID == plannerID, host.isJoystickMode(),
              host.isSceneActive(), !host.isRecoveryChecking(),
              joystick.canSetWanderEnabled, joystick.canStartWanderPlanning,
              joystick.installWanderRoute(target: target, route: planned),
              joystick.setWanderEnabled(true) else {
            if !host.isSceneActive() || host.isRecoveryChecking() || service.movementConnection == .unavailable { return false }
            failPlanning(plannerID)
            return false
        }
        joystick.clearWanderError()
        host.wanderStarted(planned)
        planningID = nil
        activeCheckpoint = nil
        interruptedCheckpoint = nil
        return true
    }

    private func failPlanning(_ plannerID: UUID) {
        guard planningID == plannerID else { return }
        pendingStart = nil
        planningID = nil
        planningTask = nil
        activeCheckpoint = nil
        interruptedCheckpoint = nil
        joystick.setWanderPlanningFailed()
    }

    // MARK: Start origin teleport

    /// The origin teleport `intentID` was acknowledged. The host clears its own
    /// origin request first, so a deferred Start sees the settled origin.
    public func originAcknowledged(_ intentID: UUID) {
        let startDeferred = deferredStart.consumeAcknowledgement(for: intentID)
        if let pending = pendingStart, pending.teleportIntentID == intentID,
           pending.plannerID == planningID {
            // The ACK also starts the position hold, whose native
            // preparation can still be busy; wait for it rather
            // than failing the first Start.
            if host.isSceneActive() && !host.isRecoveryChecking()
                && joystick.canSetWanderEnabled && joystick.canStartWanderPlanning {
                pendingStart = nil
                installAndStart(target: pending.target, route: pending.route, plannerID: pending.plannerID)
            } else {
                pendingStart?.originAcknowledged = true
            }
        } else if startDeferred {
            start()
        }
    }

    public func originNotSent(_ intentID: UUID) {
        let startDeferred = deferredStart.consumeFailure(for: intentID)
        if pendingStart?.teleportIntentID == intentID {
            let plannerID = pendingStart?.plannerID
            pendingStart = nil
            if let plannerID { failPlanning(plannerID) }
        } else if startDeferred {
            start()
        }
    }

    public func originUnconfirmed(_ intentID: UUID) {
        let failedDeferredOrigin = deferredStart.consumeFailure(for: intentID)
        if pendingStart?.teleportIntentID == intentID || failedDeferredOrigin {
            pendingStart = nil
        }
    }

    // MARK: Continuation

    /// Plans from the last ACK endpoint while the existing joystick lease is
    /// paused. A failed endpoint selection/planning gets one fresh target retry.
    public func planNextSegment(preselectedTarget: WanderTarget? = nil) {
        guard joystick.wanderEnabled, joystick.wanderNeedsTarget,
              replanningTask == nil else { return }
        let planningID = UUID()
        replanningID = planningID
        activeCheckpoint = Checkpoint(
            purpose: .continuation, origin: service.currentJoystickOrigin, target: preselectedTarget)
        replanningTask = Task { @MainActor in
            defer {
                if replanningID == planningID {
                    replanningTask = nil
                    replanningID = nil
                }
            }
            while !Task.isCancelled, joystick.phase == .pausing {
                try? await Task.sleep(for: .milliseconds(40))
            }
            guard !Task.isCancelled, replanningID == planningID else { return }
            guard host.isSceneActive(), host.isJoystickMode(), joystick.phase == .suspended,
                  joystick.suspensionReason == .targetUnavailable else {
                failReplanning(planningID)
                return
            }
            guard service.movementConnection != .unavailable else { return }
            guard let origin = service.currentJoystickOrigin else { failReplanning(planningID); return }
            for attempt in 0..<2 {
                guard !Task.isCancelled, replanningID == planningID,
                      host.isSceneActive(), host.isJoystickMode(), joystick.wanderEnabled,
                      let currentOrigin = service.currentJoystickOrigin,
                      JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) <= 1,
                      let target = (attempt == 0 ? preselectedTarget : nil)
                        ?? joystick.selectWanderTarget(from: origin) else { continue }
                activeCheckpoint = Checkpoint(purpose: .continuation, origin: origin, target: target)
                do {
                    let planned = try await planSegment(origin, target.coordinate)
                    guard !Task.isCancelled, replanningID == planningID,
                          service.movementConnection != .unavailable, host.isSceneActive(),
                          host.isJoystickMode(), joystick.wanderEnabled,
                          let currentOrigin = service.currentJoystickOrigin,
                          JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) <= 1,
                          JoystickGeodesy.distanceMeters(from: currentOrigin, to: planned.start) <= 1,
                          joystick.installNextWanderRouteAndResume(target: target, route: planned) else { continue }
                    joystick.clearWanderError()
                    activeCheckpoint = nil
                    interruptedCheckpoint = nil
                    return
                } catch is CancellationError { return }
                catch { continue }
            }
            guard !Task.isCancelled, replanningID == planningID else { return }
            guard service.movementConnection != .unavailable else { return }
            failReplanning(planningID)
        }
    }

    private func failReplanning(_ planningID: UUID) {
        guard replanningID == planningID else { return }
        replanningTask = nil
        replanningID = nil
        activeCheckpoint = nil
        interruptedCheckpoint = nil
        joystick.setWanderPlanningFailed()
    }

    // MARK: Replacement

    /// The person confirmed a new destination for the running wander.
    public func confirmDestination(_ place: MapPlace) {
        retryDestination = nil
        replan(to: place)
    }

    /// Manual input left the road: replan to the same destination and keep it for a retry.
    public func replanCurrentDestination() {
        let destination = joystick.wanderTarget?.place
        retryDestination = destination
        replan(to: destination)
    }

    /// Pauses the wander, plans a replacement segment to `destination` (or a
    /// fresh target when nil) and resumes on the same lease.
    public func replan(to destination: MapPlace?) {
        let isCompletedSegment = joystick.phase == .suspended && joystick.suspensionReason == .targetUnavailable
        if isCompletedSegment, destination != nil {
            replanningTask?.cancel()
            replanningTask = nil
            replanningID = nil
        }
        guard joystick.wanderEnabled, joystick.wanderRoute != nil, joystick.canApplyWanderTarget,
              !joystick.requiresStop, replanningTask == nil else { return }
        if destination == nil { host.destinationCleared() }
        joystick.clearWanderError()
        let planningID = UUID()
        replanningID = planningID
        activeCheckpoint = Checkpoint(
            purpose: .replacement, origin: service.currentJoystickOrigin,
            target: destination.map { WanderTarget(place: $0) })
        replanningTask = Task { @MainActor in
            defer {
                if replanningID == planningID {
                    replanningTask = nil
                    replanningID = nil
                }
            }
            joystick.markWanderNeedsReplan()
            let readyToPlan: Bool
            if isCompletedSegment {
                readyToPlan = joystick.phase == .suspended && joystick.suspensionReason == .targetUnavailable
            } else {
                readyToPlan = await joystick.pauseForWanderReplan()
            }
            guard readyToPlan, !Task.isCancelled,
                  replanningID == planningID, host.isJoystickMode(),
                  host.isSceneActive(), let origin = service.currentJoystickOrigin else {
                guard !Task.isCancelled, replanningID == planningID else { return }
                guard service.movementConnection != .unavailable else { return }
                failReplanning(planningID)
                return
            }
            let target = destination.map { WanderTarget(place: $0) }
                ?? joystick.selectWanderTarget(from: origin)
            guard let target else {
                if service.movementConnection != .unavailable { failReplanning(planningID) }
                return
            }
            activeCheckpoint = Checkpoint(purpose: .replacement, origin: origin, target: target)
            do {
                let planned = try await planSegment(origin, target.coordinate)
                guard !Task.isCancelled, replanningID == planningID,
                      service.movementConnection != .unavailable, host.isJoystickMode(),
                      let currentOrigin = service.currentJoystickOrigin,
                      host.isSceneActive(),
                      JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) <= 1,
                      JoystickGeodesy.distanceMeters(from: currentOrigin, to: planned.start) <= 1,
                      (isCompletedSegment
                        ? joystick.installNextWanderRouteAndResume(target: target, route: planned)
                        : joystick.replaceWanderRouteAndResume(target: target, route: planned)) else {
                    guard !Task.isCancelled, replanningID == planningID else { return }
                    guard service.movementConnection != .unavailable else { return }
                    failReplanning(planningID)
                    return
                }
                joystick.clearWanderError()
                activeCheckpoint = nil
                interruptedCheckpoint = nil
                retryDestination = nil
                host.segmentReplaced(planned)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, replanningID == planningID else { return }
                guard service.movementConnection != .unavailable else { return }
                failReplanning(planningID)
            }
        }
    }

    // MARK: Lifecycle

    /// Retries the planning that raised `wander.error.planningFailed`.
    public func retryFailedPlanning() {
        joystick.clearWanderError()
        if joystick.wanderEnabled && joystick.wanderNeedsTarget { planNextSegment() }
        else if joystick.wanderEnabled { replan(to: retryDestination) }
        else { start() }
    }

    public func stop() {
        cancelStartup()
        replanningTask?.cancel()
        replanningTask = nil
        replanningID = nil
        _ = joystick.setWanderEnabled(false)
    }

    /// A cancelled start leaves nothing pending, so Start is available again.
    private func cancelStartup() {
        if pendingStart != nil, joystickOrigin.request.isSetting { joystickOrigin.cancel() }
        planningTask?.cancel()
        planningTask = nil
        planningID = nil
        pendingStart = nil
        activeCheckpoint = nil
        deferredStart.cancel()
    }

    /// The scene left the foreground or the connection dropped: drop planning
    /// that has not committed and remember it for `resumePending()`.
    public func cancelUncommitted() {
        if let activeCheckpoint { interruptedCheckpoint = activeCheckpoint }
        activeCheckpoint = nil
        if pendingStart == nil {
            planningTask?.cancel()
            planningTask = nil
            planningID = nil
        }
        replanningTask?.cancel()
        replanningTask = nil
        replanningID = nil
    }

    /// Leaving the joystick tab or the map drops every planning state.
    public func cancelAll() {
        planningTask?.cancel()
        planningID = nil
        replanningTask?.cancel()
        replanningTask = nil
        replanningID = nil
        pendingStart = nil
        activeCheckpoint = nil
        interruptedCheckpoint = nil
        deferredStart.cancel()
    }

    /// Resumes planning interrupted by the scene, recovery or the connection.
    public func resumePending() {
        guard host.isSceneActive(), host.isJoystickMode(), !host.isRecoveryChecking(),
              service.movementConnection == .available else { return }
        if let pending = pendingStart, pending.originAcknowledged,
           pending.plannerID == planningID,
           joystick.canSetWanderEnabled, joystick.canStartWanderPlanning {
            pendingStart = nil
            installAndStart(target: pending.target, route: pending.route, plannerID: pending.plannerID)
            return
        }
        if let checkpoint = interruptedCheckpoint {
            interruptedCheckpoint = nil
            switch checkpoint.purpose {
            case .startup:
                start(preselectedOrigin: checkpoint.origin, preselectedTarget: checkpoint.target)
            case .replacement:
                guard joystick.wanderEnabled else { return }
                replan(to: checkpoint.target?.place ?? retryDestination ?? joystick.wanderTarget?.place)
            case .continuation:
                guard joystick.wanderEnabled else { return }
                planNextSegment(preselectedTarget: checkpoint.target)
            }
            return
        }
        guard joystick.wanderEnabled else { return }
        if joystick.wanderNeedsTarget, joystick.phase == .suspended,
           joystick.suspensionReason == .targetUnavailable {
            planNextSegment()
        } else if joystick.wanderNeedsReplan {
            let destination = retryDestination ?? joystick.wanderTarget?.place
            retryDestination = destination
            replan(to: destination)
        }
    }
}
