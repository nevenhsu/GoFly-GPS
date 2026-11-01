import GoFlyCore
import SwiftUI

struct GoFlySearchPasteWarning: Identifiable {
    let id = UUID()
    let localizationKey: String
}

/// The one floating notice above the map, in priority order. It is its own
/// view, built only from observed owners, bindings and values, so SwiftUI can
/// skip it when nothing it reads has changed.
struct GoFlyMapToastStack: View {
    @ObservedObject var service: ServiceController
    @ObservedObject var route: RouteExecutionController
    @ObservedObject var joystick: JoystickMovementController
    @ObservedObject var recovery: ConnectionRecoveryController
    @ObservedObject var continuation: MovementContinuationController
    @ObservedObject var positionHold: PositionHoldController
    @ObservedObject var joystickOrigin: JoystickOriginController
    let wander: WanderPlanningCoordinator
    @Binding var notices: NoticeState
    @Binding var searchPasteWarning: GoFlySearchPasteWarning?
    @Binding var showingSettings: Bool
    let mode: SessionMapMode
    let sceneSettled: Bool
    /// A paused or interrupted task the person can resume.
    let isResumeState: Bool
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    private var unconfirmedID: UUID? { service.pointState.unconfirmedID }
    private var unconfirmedFailure: DeviceServiceFailure? { service.pointState.unconfirmedFailure }
    private var isUnconfirmedTeleportFailure: Bool {
        mode == .teleport
            && unconfirmedFailure.map { SessionStatusErrors.reportsFailure($0.rawValue) } == true
            && notices.showsUnconfirmed(unconfirmedID)
    }

    private func retryInterruptedRoute() { goFlyRetryInterruptedRoute(route: route, recovery: recovery) }

    /// The person pressed Pause: the resume panel already says so, no toast.
    private var isUserPausedRoute: Bool {
        mode == .route && route.phase == .paused && route.suspensionReason == nil
    }

    /// The person paused the wander: same as a route, no toast. A recovery
    /// suspension is covered by `recovery.isSilentRepairInProgress` instead.
    /// One connection-lost banner (with Retry) owns the notice while a silent
    /// repair runs and after it failed: no second service-error or pause toast.
    private var repairOwnsNotice: Bool {
        recovery.isSilentRepairInProgress || recovery.canRetryAutomaticRepair
    }

    private var isUserPausedWander: Bool {
        mode == .joystick && joystick.wanderEnabled && joystick.phase == .paused
            && joystick.suspensionReason == nil
    }

    /// The one toast button for an error key. Retry stays in the current mode:
    /// teleport retries its prepared operation, route its planning, wander its
    /// stream. Only when none applies does it reconnect the device.
    private func issueButton(for key: String, retry: (() -> Void)? = nil,
                             fix: (() -> Void)? = nil) -> (title: String?, action: (() -> Void)?) {
        goFlyIssueButton(for: key, retry: retry ?? { retryInCurrentMode() }, fix: fix,
                         settings: { showingSettings = true })
    }

    private func retryInCurrentMode() {
        switch mode {
        case .teleport:
            if let operation = service.preparedOperation, case .failed = operation.state {
                _ = service.retryPreparedOperation(id: operation.id)
            } else { reconnectDevice() }
        case .route:
            if route.error == .planningFailed { _ = route.retryPlanning() } else { reconnectDevice() }
        case .joystick:
            if joystick.wanderEnabled, joystick.canRetryWander { _ = joystick.retryWander() } else { reconnectDevice() }
        }
    }

    /// During a task the recovery controller repairs the connection and
    /// continues the original movement.
    private func reconnectDevice() {
        recovery.checkConnection()
    }

    var body: some View {
        VStack(spacing: 8) {
            if let searchPasteWarning {
                GoFlyStatusBanner(
                    tone: .warning,
                    title: goFlyString(searchPasteWarning.localizationKey),
                    onDismiss: { self.searchPasteWarning = nil },
                    identifier: "map.searchPasteWarning",
                    isFloating: true
                )
                .task(id: searchPasteWarning.id) {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard self.searchPasteWarning?.id == searchPasteWarning.id else { return }
                    self.searchPasteWarning = nil
                }
            }
            if network.shouldShowWiFiError {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString("wifi.error.title"),
                    message: goFlyString("wifi.error.message"),
                    actionTitle: goFlyString("common.retry"),
                    onAction: { network.recheck() },
                    onDismiss: { network.dismissNotice() },
                    identifier: "map.wifiError",
                    isFloating: true
                )
            }
            if let key = notices.favoriteRouteKey {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString(key),
                    onDismiss: { notices.clearFavoriteRouteFailure() },
                    identifier: "route.favoriteSaveError",
                    isFloating: true
                )
            }
            if joystick.wanderError == .planningFailed, mode == .joystick {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString("wander.error.planningFailed"),
                    actionTitle: goFlyString("common.retry"),
                    onAction: { wander.retryFailedPlanning() },
                    onDismiss: { joystick.clearWanderError() },
                    identifier: "joystick.wanderPlanningError",
                    isFloating: true
                )
            }
            if let error = service.error, !repairOwnsNotice, !isUnconfirmedTeleportFailure,
               SessionStatusErrors.reportsFailure(error.rawValue), !notices.isDismissed(.serviceError) {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString(error.rawValue),
                    message: goFlyString("status.repairGuidance"),
                    actionTitle: issueButton(for: error.rawValue).title,
                    onAction: issueButton(for: error.rawValue).action,
                    onDismiss: { notices.dismiss(.serviceError) },
                    identifier: "map.serviceError",
                    isFloating: true
                )
            }
            if let failure = unconfirmedFailure, SessionStatusErrors.reportsFailure(failure.rawValue),
               notices.showsUnconfirmed(unconfirmedID) {
                let isTeleportFailure = mode == .teleport
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString(isTeleportFailure ? "teleport.failure.toast.title" : failure.rawValue),
                    message: isTeleportFailure
                        ? goFlyString("teleport.failure.toast.message")
                        : goFlyString("teleport.positionUnconfirmed") + " " + goFlyString("operation.failureGuidance"),
                    actionTitle: goFlyString(isTeleportFailure ? "common.retry" : "operation.settings"),
                    onAction: {
                        if isTeleportFailure { recovery.checkConnection() }
                        else { showingSettings = true }
                    },
                    onDismiss: { notices.leaveUnconfirmed(unconfirmedID) },
                    identifier: "map.unconfirmedFailure",
                    isFloating: true
                )
            }
            if case .failed(let failure)? = service.preparedOperation?.state,
               SessionStatusErrors.reportsFailure(failure.rawValue), !isUnconfirmedTeleportFailure {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString(failure.rawValue),
                    message: goFlyString("operation.failureGuidance"),
                    actionTitle: goFlyString("operation.retry"),
                    onAction: {
                        if let id = service.preparedOperation?.id { _ = service.retryPreparedOperation(id: id) }
                    },
                    onDismiss: {
                        if let id = service.preparedOperation?.id { _ = service.cancelPreparation(id: id) }
                    },
                    identifier: "map.operationFailure",
                    isFloating: true
                )
            }
            if let error = joystick.error, SessionStatusErrors.reportsFailure(error.localizationKey),
               mode == .joystick, !notices.isDismissed(.joystickError) {
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString(error.localizationKey),
                    message: goFlyString("status.repairGuidance"),
                    actionTitle: issueButton(for: error.localizationKey).title,
                    onAction: issueButton(for: error.localizationKey).action,
                    onDismiss: { notices.dismiss(.joystickError) },
                    identifier: "joystick.error",
                    isFloating: true
                )
            }
            if let error = joystick.wanderError, mode == .joystick, error != .planningFailed {
                GoFlyStatusBanner(
                    tone: .warning,
                    title: goFlyString(error.localizationKey),
                    message: goFlyString("status.repairGuidance"),
                    actionTitle: joystick.canRetryWander ? goFlyString("operation.retry") : nil,
                    onAction: joystick.canRetryWander ? { _ = joystick.retryWander() } : nil,
                    onDismiss: { joystick.clearWanderError() },
                    identifier: "joystick.wanderError",
                    isFloating: true
                )
            }
            if let error = route.error, SessionStatusErrors.reportsFailure(error.localizationKey),
               mode == .route, !notices.isDismissed(.routeError) {
                let routeIssueButton = issueButton(for: error.localizationKey,
                                                   fix: { _ = route.fixPlanningOrder() })
                GoFlyStatusBanner(
                    tone: .danger,
                    title: goFlyString("route.error.shortTitle"),
                    message: goFlyString(error.localizationKey),
                    actionTitle: routeIssueButton.title,
                    onAction: routeIssueButton.action,
                    onDismiss: { notices.dismiss(.routeError) },
                    identifier: "route.error",
                    actionEnabled: !route.isFixingPlanningOrder,
                    actionInProgress: route.isFixingPlanningOrder,
                    actionProgressAccessibilityLabel: goFlyString("route.fixing"),
                    actionIdentifier: "route.error.action",
                    isFloating: true
                )
            }
            if let key = recovery.noticeKey, !notices.isDismissed(.recovery), !isUnconfirmedTeleportFailure {
                let cold = recovery.requiresColdConfirmation
                let tone: GoFlyStatusTone = key == "recovery.connectionRecovered" ? .success : .danger
                GoFlyStatusBanner(
                    tone: tone,
                    title: goFlyString(key),
                    message: key == "recovery.connectionRecovered" ? nil : goFlyString("recovery.connectionGuidance"),
                    actionTitle: key == "recovery.connectionRecovered" ? nil : goFlyString(cold ? "toast.restore" : "common.retry"),
                    onAction: {
                        if cold { _ = service.restoreGPS() }
                        else { recovery.checkConnection() }
                    },
                    onDismiss: { notices.dismiss(.recovery) },
                    identifier: "recovery.connectionBanner",
                    actionEnabled: cold ? service.canRestoreGPS : recovery.canCheck,
                    actionIdentifier: cold ? "recovery.restoreGPS" : "recovery.checkConnection",
                    titleIdentifier: "recovery.notice",
                    isFloating: true
                )
            }
            if sceneSettled, !repairOwnsNotice, !isUnconfirmedTeleportFailure,
               !isUserPausedRoute, !isUserPausedWander, (continuation.noticeKey != nil && !notices.isDismissed(.continuation)) || isResumeState {
            let routePaused = mode == .route && (route.phase == .paused || route.phase == .interrupted)
            let holdPaused = positionHold.phase == .paused || positionHold.phase == .completed
            let wanderPaused = mode == .joystick && joystick.wanderEnabled && !joystick.isAwaitingNextTarget
                && [.paused, .suspended, .interrupted].contains(joystick.phase)

            let title: String = routePaused ? goFlyString("route.pausedToast.title")
                : (holdPaused ? goFlyString("background.positionPaused")
                : (wanderPaused ? goFlyString("joystick.wanderPaused") : goFlyString(continuation.noticeKey ?? "background.positionPaused")))

            let message: String = routePaused ? goFlyString("route.pausedToast.message")
                : (holdPaused ? goFlyString("background.positionPaused.message") : goFlyString("status.repairGuidance"))

                GoFlyStatusBanner(
                    tone: .warning,
                    title: title,
                    message: message,
                    actionTitle: goFlyString(routePaused || holdPaused ? "common.continue" : "common.retry"),
                    onAction: {
                        if routePaused { if route.phase == .interrupted { retryInterruptedRoute() } else { _ = route.resume() } }
                        else if holdPaused { _ = positionHold.retry() }
                        else if wanderPaused { _ = joystick.resume() }
                        else { showingSettings = true }
                    },
                    onDismiss: { notices.dismiss(.continuation) },
                    identifier: "map.continuationNotice",
                    actionEnabled: routePaused ? (route.phase == .interrupted || route.canResume) : (holdPaused ? positionHold.canRetry : true),
                    isFloating: true
                )
            }
        }
    }
}

/// D10 重試: repairs the connection of the interrupted route; on success the route continues from where it stopped.
@MainActor
func goFlyRetryInterruptedRoute(route: RouteExecutionController, recovery: ConnectionRecoveryController) {
    guard route.phase == .interrupted else { return }
    if recovery.canRetryAutomaticRepair || recovery.canCheck { recovery.checkConnection() }
}

extension PointMoveState {
    var unconfirmedID: UUID? {
        if case .unconfirmed(let intent, _) = self { return intent.id }
        return nil
    }
    var unconfirmedFailure: DeviceServiceFailure? {
        if case .unconfirmed(_, let failure) = self { return failure }
        return nil
    }
}
