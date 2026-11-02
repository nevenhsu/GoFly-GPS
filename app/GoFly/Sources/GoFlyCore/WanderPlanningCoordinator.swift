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

    /// `triggers` fires when state the host reads changes (scene activity,
    /// recovery checking); service and joystick changes are observed directly.
    public init(service: ServiceController, joystick: JoystickMovementController,
                origin: JoystickOriginController,
                triggers: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
                planSegment: @escaping SegmentPlanner) {
        self.service = service; self.joystick = joystick; self.joystickOrigin = origin
        self.planSegment = planSegment
        originSubscription = origin.$request.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStarting() }
        triggerSubscription = Publishers.Merge3(
            service.objectWillChange.map { _ in () }, joystick.objectWillChange.map { _ in () }, triggers)
            .sink { [weak self] in self?.queueTriggerEvaluation() }
    }
    private var originSubscription: AnyCancellable?
    private var triggerSubscription: AnyCancellable?

    public func attach(_ host: WanderPlanningHost) {
        self.host = host
        queueTriggerEvaluation()
    }

    /// The person entered or left the joystick tab.
    public func joystickModeDidChange(_ isJoystickMode: Bool) {
        if !isJoystickMode { cancelAll() }
        else if !host.isRecoveryChecking() { resumePending() }
    }

    // MARK: Triggers

    /// What planning waits on. Each evaluation compares it with the last one,
    /// so every rule below fires on a change, never once per publish.
    private struct Triggers: Equatable {
        var sceneActive = false
        var recoveryChecking = false
        var connection: MovementConnectionState?
        var wanderNeedsReplan = false
        var wanderNeedsTarget = false
        var joystickMoving = false
        var isClear: Bool { sceneActive && !recoveryChecking && connection == .available }
    }
    private var lastTriggers = Triggers()
    private var triggerEvaluationQueued = false

    /// Publishers fire before the change; evaluate once after it settles.
    private func queueTriggerEvaluation() {
        guard !triggerEvaluationQueued else { return }
        triggerEvaluationQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.triggerEvaluationQueued = false
            self.evaluateTriggers()
        }
    }

    private func evaluateTriggers() {
        let now = Triggers(sceneActive: host.isSceneActive(), recoveryChecking: host.isRecoveryChecking(),
                           connection: service.movementConnection,
                           wanderNeedsReplan: joystick.wanderNeedsReplan, wanderNeedsTarget: joystick.wanderNeedsTarget,
                           joystickMoving: joystick.phase == .moving)
        let last = lastTriggers
        lastTriggers = now
        // Leaving the foreground or losing the connection drops uncommitted planning.
        if (last.sceneActive && !now.sceneActive)
            || (now.connection != last.connection && now.connection != .available) {
            cancelUncommitted()
        }
        // Becoming clear resumes whatever was interrupted. While clear, an
        // acknowledged start installs as soon as the joystick owner admits it,
        // whichever change made that possible.
        if now.isClear && (!last.isClear || hasAcknowledgedPendingStart) {
            resumePending()
        }
        if now.wanderNeedsReplan && !last.wanderNeedsReplan && now.joystickMoving {
            replanCurrentDestination()
        }
        if now.wanderNeedsTarget && !last.wanderNeedsTarget {
            planNextSegment()
        }
        if now.joystickMoving && !last.joystickMoving && now.wanderNeedsReplan {
            replan(to: joystick.wanderTarget?.place, rejoiningOnFailure: true)
        }
    }

    public var canRequestStart: Bool {
        let origin = joystickOrigin.request
        return joystick.canStartWanderPlanning || (origin.isSetting && origin.intentID != nil
            && host.isJoystickMode() && !joystick.wanderEnabled && !joystick.requiresStop)
    }
    /// The start teleport was acknowledged but the wander waits for native work to drain.
    public var hasAcknowledgedPendingStart: Bool { pendingStart?.originAcknowledged == true }
    /// The teleport intent is the automatic origin of a wander start, either
    /// planned here or an origin fix a Start press is waiting for.
    public func isStartOrigin(_ intentID: UUID) -> Bool {
        pendingStart?.teleportIntentID == intentID || deferredStart.originIntentID == intentID
    }

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
                joystick.wanderStarting(origin)
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
    /// paused, or, in the background, while it waits in place. A failed
    /// endpoint selection/planning gets fresh target retries.
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
            // A paused segment end plans only in the foreground; a background
            // run keeps its lease waiting in place and plans there.
            let inPlace = joystick.isAwaitingNextTargetInPlace
            let canContinue = { [joystick, host] in
                host.isJoystickMode() && joystick.wanderEnabled
                    && (inPlace ? joystick.isAwaitingNextTargetInPlace : host.isSceneActive())
            }
            guard canContinue(), inPlace || (joystick.phase == .suspended
                  && joystick.suspensionReason == .targetUnavailable) else {
                failReplanning(planningID)
                return
            }
            guard service.movementConnection != .unavailable else { return }
            guard let origin = service.currentJoystickOrigin else { failReplanning(planningID); return }
            // MapKit may refuse a background request for a moment; nobody can
            // tap Retry there, so the run tries longer before it pauses.
            let attempts = inPlace ? 5 : 2
            for attempt in 0..<attempts {
                if inPlace, attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
                guard !Task.isCancelled, replanningID == planningID, canContinue(),
                      let currentOrigin = service.currentJoystickOrigin,
                      JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) <= 1,
                      let target = (attempt == 0 ? preselectedTarget : nil)
                        ?? joystick.selectWanderTarget(from: origin) else { continue }
                activeCheckpoint = Checkpoint(purpose: .continuation, origin: origin, target: target)
                do {
                    let planned = try await planSegment(origin, target.coordinate)
                    guard !Task.isCancelled, replanningID == planningID,
                          service.movementConnection != .unavailable, canContinue(),
                          let currentOrigin = service.currentJoystickOrigin,
                          JoystickGeodesy.distanceMeters(from: currentOrigin, to: origin) <= 1,
                          JoystickGeodesy.distanceMeters(from: currentOrigin, to: planned.start) <= 1,
                          inPlace ? joystick.installNextWanderRouteInPlace(target: target, route: planned)
                                  : joystick.installNextWanderRouteAndResume(target: target, route: planned)
                    else { continue }
                    joystick.clearWanderError()
                    activeCheckpoint = nil
                    interruptedCheckpoint = nil
                    return
                } catch is CancellationError { return }
                catch let throttled as RoutePlanningThrottled where inPlace {
                    Diagnostics.shared.record("wander.planThrottled", category: .movement, level: .notice)
                    try? await Task.sleep(for: throttled.retryAfter)
                }
                catch {
                    Diagnostics.shared.record("wander.planFailed", category: .movement, level: .notice, [
                        "attempt": .count(attempt), "inPlace": .flag(inPlace)
                    ])
                }
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
        joystick.stopAwaitingNextTargetInPlace()
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
        replan(to: destination, rejoiningOnFailure: true)
    }

    /// Pauses the wander, plans a replacement segment to `destination` (or a
    /// fresh target when nil) and resumes on the same lease.
    public func replan(to destination: MapPlace?) { replan(to: destination, rejoiningOnFailure: false) }

    /// After a manual override, a failed plan from the arrow is no error: the
    /// wander walks straight back onto its current route and continues it.
    private func replan(to destination: MapPlace?, rejoiningOnFailure: Bool) {
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
            let rejoins = rejoiningOnFailure && !isCompletedSegment
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
                if service.movementConnection != .unavailable,
                   !(rejoins && rejoinCurrentRoute(planningID)) { failReplanning(planningID) }
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
                    if !(rejoins && rejoinCurrentRoute(planningID)) { failReplanning(planningID) }
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
                if !(rejoins && rejoinCurrentRoute(planningID)) { failReplanning(planningID) }
            }
        }
    }

    /// Resumes the paused wander on a straight walk from the arrow to the
    /// nearest point of its current route not yet passed, then the rest of it.
    private func rejoinCurrentRoute(_ planningID: UUID) -> Bool {
        guard replanningID == planningID, host.isJoystickMode(), host.isSceneActive(),
              let origin = service.currentJoystickOrigin, let target = joystick.wanderTarget,
              let route = joystick.wanderRoute,
              let rejoin = Self.rejoinRoute(from: origin, onto: route, passedMeters: joystick.wanderProgressMeters),
              joystick.replaceWanderRouteAndResume(target: target, route: rejoin) else { return false }
        Diagnostics.shared.record("wander.rejoinedRoute", category: .movement, level: .notice, [
            "rejoin_m": .number(JoystickGeodesy.distanceMeters(from: origin, to: rejoin.points[min(1, rejoin.points.count - 1)]), digits: 1)
        ])
        joystick.clearWanderError()
        activeCheckpoint = nil
        interruptedCheckpoint = nil
        retryDestination = nil
        host.segmentReplaced(rejoin)
        return true
    }

    static func rejoinRoute(from origin: GeoCoordinate, onto route: PlannedRoute, passedMeters: Double) -> PlannedRoute? {
        let ahead = route.points.indices.filter { route.cumulativeDistancesMeters[$0] >= passedMeters }
        guard let nearest = ahead.min(by: {
            JoystickGeodesy.distanceMeters(from: origin, to: route.points[$0])
                < JoystickGeodesy.distanceMeters(from: origin, to: route.points[$1])
        }) else { return nil }
        var points = Array(route.points[nearest...])
        if JoystickGeodesy.distanceMeters(from: origin, to: points[0]) > 1 { points.insert(origin, at: 0) }
        return points.count >= 2 ? try? PlannedRoute(points: points) : nil
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
