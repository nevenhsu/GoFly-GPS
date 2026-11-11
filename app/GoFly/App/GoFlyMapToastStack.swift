import GoFlyCore
import SwiftUI

struct GoFlySearchPasteWarning: Identifiable {
    let id = UUID()
    let localizationKey: String
}

/// The floating notices above the map, in `MapNoticeBoard` order. It is its
/// own view, built only from observed owners, bindings and values, so SwiftUI
/// can skip it when nothing it reads has changed.
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
    @ObservedObject private var localNetwork = GoFlyLocalNetworkAuthorization.shared
    @ObservedObject private var support = GoFlySupportPreparation.shared
    @Environment(\.scenePhase) private var scenePhase

    private var unconfirmedID: UUID? { service.pointState.unconfirmedID }

    private func retryInterruptedRoute() { goFlyRetryInterruptedRoute(route: route, recovery: recovery) }

    private var boardInputs: MapNoticeInputs {
        var preparedFailure: DeviceServiceFailure?
        if case .failed(let failure)? = service.preparedOperation?.state { preparedFailure = failure }
        return MapNoticeInputs(
            mode: mode, sceneSettled: sceneSettled, notices: notices,
            activeMovement: ActiveMovement(route: route, joystick: joystick, positionHold: positionHold),
            isResumeState: isResumeState, serviceError: service.error,
            unconfirmedID: unconfirmedID, unconfirmedFailure: service.pointState.unconfirmedFailure,
            preparedFailure: preparedFailure, joystickErrorKey: joystick.error?.localizationKey,
            wanderError: joystick.wanderError, canRetryWander: joystick.canRetryWander,
            routeErrorKey: route.error?.localizationKey, isFixingRouteOrder: route.isFixingPlanningOrder,
            recoveryNoticeKey: recovery.noticeKey, requiresColdConfirmation: recovery.requiresColdConfirmation,
            repairOwnsNotice: recovery.isSilentRepairInProgress || recovery.canRetryAutomaticRepair,
            isWiFiConnected: network.isWiFiConnected,
            localNetworkDenied: localNetwork.authorization == .denied,
            continuationNoticeKey: continuation.noticeKey)
    }

    private static let supportKey = DeviceServiceFailure.devicePreparationRequired.rawValue

    /// Sideloaded installs show the DDI modal (DDI.5–6) for a device-support
    /// error instead of a toast; Mac installs keep the USB toast.
    private var supportNotice: MapNotice? {
        guard support.appliesToThisInstall else { return nil }
        return MapNoticeBoard.notices(for: boardInputs).first { Self.supportKey == Self.errorKey(of: $0) }
    }

    private var visibleNotices: [MapNotice] {
        let notices = MapNoticeBoard.notices(for: boardInputs)
        guard support.appliesToThisInstall else { return notices }
        return notices.filter { Self.errorKey(of: $0) != Self.supportKey }
    }

    private static func errorKey(of notice: MapNotice) -> String? {
        switch notice {
        case .serviceError(let key), .preparedOperationFailed(let key), .joystickError(let key):
            key
        case .routeError(let key, _):
            key
        default:
            nil
        }
    }

    /// Repeats what failed once support is ready.
    private func supportRetry(for notice: MapNotice) -> () -> Void {
        if case .preparedOperationFailed = notice {
            return {
                if let id = service.preparedOperation?.id { _ = service.retryPreparedOperation(id: id) }
            }
        }
        return { retryInCurrentMode() }
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
                    title: goFlyIssueTitle(for: searchPasteWarning.localizationKey),
                    message: goFlyString(searchPasteWarning.localizationKey),
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
            ForEach(visibleNotices) { notice in
                banner(for: notice)
            }
        }
        .onChange(of: supportNotice?.id, initial: true) { _, id in
            guard id != nil, let notice = supportNotice else { return }
            support.presentForMap(retry: supportRetry(for: notice))
        }
        .sheet(isPresented: $support.isMapModalPresented, onDismiss: { support.closeMap() }) {
            GoFlySupportModal(context: .map, preparation: support,
                              onRetry: { support.retryFromMap() },
                              onClose: { support.closeMap() })
        }
    }

    @ViewBuilder
    private func banner(for notice: MapNotice) -> some View {
        switch notice {
        case .favoriteRouteFailure(let key):
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
                onDismiss: { notices.clearFavoriteRouteFailure() },
                identifier: "route.favoriteSaveError",
                isFloating: true
            )
        case .wanderPlanningFailed:
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: WanderSelectionFailure.planningFailed.rawValue),
                message: goFlyString(WanderSelectionFailure.planningFailed.rawValue),
                actionTitle: goFlyString("common.retry"),
                onAction: { wander.retryFailedPlanning() },
                onDismiss: { joystick.clearWanderError() },
                identifier: "joystick.wanderPlanningError",
                isFloating: true
            )
        case .serviceError(let key):
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
                actionTitle: issueButton(for: key).title,
                onAction: issueButton(for: key).action,
                onDismiss: { notices.dismiss(.serviceError) },
                identifier: "map.serviceError",
                isFloating: true
            )
        case .unconfirmedPosition(let key, let inTeleport):
            let id = unconfirmedID
            GoFlyStatusBanner(
                tone: .danger,
                title: inTeleport ? goFlyString("teleport.failure.toast.title") : goFlyIssueTitle(for: key),
                message: goFlyString(inTeleport ? "teleport.failure.toast.message" : "teleport.positionUnconfirmed"),
                actionTitle: goFlyString(inTeleport ? "common.retry" : "operation.settings"),
                onAction: {
                    if inTeleport { recovery.checkConnection() }
                    else { showingSettings = true }
                },
                onDismiss: { notices.leaveUnconfirmed(id) },
                identifier: "map.unconfirmedFailure",
                isFloating: true
            )
        case .preparedOperationFailed(let key):
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
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
        case .joystickError(let key):
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
                actionTitle: issueButton(for: key).title,
                onAction: issueButton(for: key).action,
                onDismiss: { notices.dismiss(.joystickError) },
                identifier: "joystick.error",
                isFloating: true
            )
        case .wanderSelectionError(let key, let canRetry):
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
                actionTitle: canRetry ? goFlyString("operation.retry") : nil,
                onAction: canRetry ? { _ = joystick.retryWander() } : nil,
                onDismiss: { joystick.clearWanderError() },
                identifier: "joystick.wanderError",
                isFloating: true
            )
        case .routeError(let key, let isFixing):
            let routeIssueButton = issueButton(for: key, fix: { _ = route.fixPlanningOrder() })
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyIssueTitle(for: key),
                message: goFlyString(key),
                actionTitle: routeIssueButton.title,
                onAction: routeIssueButton.action,
                onDismiss: { notices.dismiss(.routeError) },
                identifier: "route.error",
                actionEnabled: !isFixing,
                actionInProgress: isFixing,
                actionProgressAccessibilityLabel: goFlyString("route.fixing"),
                actionIdentifier: "route.error.action",
                isFloating: true
            )
        case .connection(let key, let cold):
            let recovered = key == "recovery.connectionRecovered"
            GoFlyStatusBanner(
                tone: recovered ? .success : .danger,
                title: goFlyString(key),
                message: recovered ? nil : goFlyString("recovery.connectionGuidance"),
                actionTitle: recovered ? nil : goFlyString(cold ? "toast.restore" : "common.retry"),
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
        case .connectionIssue(let issue):
            GoFlyConnectionIssueBanner(issue: issue, identifier: "recovery.connectionBanner",
                                       titleIdentifier: "recovery.notice",
                                       onDismiss: { notices.dismiss(.recovery) })
        case .resume(let resume):
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString(resume.titleKey),
                message: goFlyString(resume.messageKey),
                actionTitle: goFlyString(resume.actionTitleKey),
                onAction: {
                    switch resume.action {
                    case .retryInterruptedRoute: retryInterruptedRoute()
                    case .resumeRoute: _ = route.resume()
                    case .retryPositionHold: _ = positionHold.retry()
                    case .resumeWander: _ = joystick.resume()
                    case nil: showingSettings = true
                    }
                },
                onDismiss: { notices.dismiss(.continuation) },
                identifier: "map.continuationNotice",
                actionEnabled: resume.actionEnabled,
                isFloating: true
            )
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
