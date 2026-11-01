import Foundation

/// One floating notice above the map. The map view only renders these and
/// wires each action; which notices exist, and which suppress others, is
/// decided by `MapNoticeBoard`.
public enum MapNotice: Equatable, Sendable, Identifiable {
    case favoriteRouteFailure(key: String)
    case wanderPlanningFailed
    case serviceError(key: String)
    /// A point whose outcome is unknown. In the teleport tab it is the teleport failure.
    case unconfirmedPosition(key: String, inTeleport: Bool)
    case preparedOperationFailed(key: String)
    case joystickError(key: String)
    case wanderSelectionError(key: String, canRetry: Bool)
    case routeError(key: String, isFixing: Bool)
    /// Connection lost or recovered. `coldConfirmation` offers Restore instead of Retry.
    case connection(key: String, coldConfirmation: Bool)
    case resume(ResumeNotice)

    /// At most one notice of each case shows at a time.
    public var id: String {
        switch self {
        case .favoriteRouteFailure: "favoriteRouteFailure"
        case .wanderPlanningFailed: "wanderPlanningFailed"
        case .serviceError: "serviceError"
        case .unconfirmedPosition: "unconfirmedPosition"
        case .preparedOperationFailed: "preparedOperationFailed"
        case .joystickError: "joystickError"
        case .wanderSelectionError: "wanderSelectionError"
        case .routeError: "routeError"
        case .connection: "connection"
        case .resume: "resume"
        }
    }

    public struct ResumeNotice: Equatable, Sendable {
        public let titleKey: String
        public let messageKey: String
        public let actionTitleKey: String
        /// The movement this notice continues; nil opens Settings.
        public let action: ActiveMovement.ResumeAction?
        public let actionEnabled: Bool
    }
}

/// What the map's notices depend on, read once from the domain owners.
public struct MapNoticeInputs: Sendable {
    public var mode: SessionMapMode
    /// One second after returning to the foreground; resume notices wait for it.
    public var sceneSettled: Bool
    public var notices: NoticeState
    public var activeMovement: ActiveMovement?
    /// A paused or interrupted task the person can resume in this tab.
    public var isResumeState: Bool
    public var serviceError: DeviceServiceFailure?
    public var unconfirmedID: UUID?
    public var unconfirmedFailure: DeviceServiceFailure?
    public var preparedFailure: DeviceServiceFailure?
    public var joystickErrorKey: String?
    public var wanderError: WanderSelectionFailure?
    public var canRetryWander: Bool
    public var routeErrorKey: String?
    public var isFixingRouteOrder: Bool
    public var recoveryNoticeKey: String?
    public var requiresColdConfirmation: Bool
    /// A silent repair runs or failed and can be retried: its connection notice owns the map.
    public var repairOwnsNotice: Bool
    public var isWiFiConnected: Bool
    public var continuationNoticeKey: String?

    public init(mode: SessionMapMode, sceneSettled: Bool = true, notices: NoticeState = NoticeState(),
                activeMovement: ActiveMovement? = nil, isResumeState: Bool = false,
                serviceError: DeviceServiceFailure? = nil, unconfirmedID: UUID? = nil,
                unconfirmedFailure: DeviceServiceFailure? = nil, preparedFailure: DeviceServiceFailure? = nil,
                joystickErrorKey: String? = nil, wanderError: WanderSelectionFailure? = nil,
                canRetryWander: Bool = false, routeErrorKey: String? = nil, isFixingRouteOrder: Bool = false,
                recoveryNoticeKey: String? = nil, requiresColdConfirmation: Bool = false,
                repairOwnsNotice: Bool = false, isWiFiConnected: Bool = true,
                continuationNoticeKey: String? = nil) {
        self.mode = mode; self.sceneSettled = sceneSettled; self.notices = notices
        self.activeMovement = activeMovement; self.isResumeState = isResumeState
        self.serviceError = serviceError; self.unconfirmedID = unconfirmedID
        self.unconfirmedFailure = unconfirmedFailure; self.preparedFailure = preparedFailure
        self.joystickErrorKey = joystickErrorKey; self.wanderError = wanderError
        self.canRetryWander = canRetryWander; self.routeErrorKey = routeErrorKey
        self.isFixingRouteOrder = isFixingRouteOrder; self.recoveryNoticeKey = recoveryNoticeKey
        self.requiresColdConfirmation = requiresColdConfirmation; self.repairOwnsNotice = repairOwnsNotice
        self.isWiFiConnected = isWiFiConnected; self.continuationNoticeKey = continuationNoticeKey
    }
}

/// Decides which notices float above the map, top to bottom.
public enum MapNoticeBoard {
    public static func notices(for input: MapNoticeInputs) -> [MapNotice] {
        let reports = SessionStatusErrors.reportsFailure
        let notices = input.notices
        let showsUnconfirmed = input.unconfirmedFailure.map { reports($0.rawValue) } == true
            && notices.showsUnconfirmed(input.unconfirmedID)
        // The teleport tab's failed point owns the notice: no service, prepared,
        // connection or resume notice repeats it.
        let teleportFailureOwns = input.mode == .teleport && showsUnconfirmed
        var result: [MapNotice] = []

        if let key = notices.favoriteRouteKey { result.append(.favoriteRouteFailure(key: key)) }
        if input.wanderError == .planningFailed, input.mode == .joystick { result.append(.wanderPlanningFailed) }
        if let error = input.serviceError, !input.repairOwnsNotice, !teleportFailureOwns,
           reports(error.rawValue), !notices.isDismissed(.serviceError) {
            result.append(.serviceError(key: error.rawValue))
        }
        if showsUnconfirmed, let failure = input.unconfirmedFailure {
            result.append(.unconfirmedPosition(key: failure.rawValue, inTeleport: input.mode == .teleport))
        }
        if let failure = input.preparedFailure, reports(failure.rawValue), !teleportFailureOwns {
            result.append(.preparedOperationFailed(key: failure.rawValue))
        }
        if let key = input.joystickErrorKey, reports(key), input.mode == .joystick,
           !notices.isDismissed(.joystickError) {
            result.append(.joystickError(key: key))
        }
        if let error = input.wanderError, input.mode == .joystick, error != .planningFailed {
            result.append(.wanderSelectionError(key: error.localizationKey, canRetry: input.canRetryWander))
        }
        if let key = input.routeErrorKey, reports(key), input.mode == .route, !notices.isDismissed(.routeError) {
            result.append(.routeError(key: key, isFixing: input.isFixingRouteOrder))
        }
        // Losing Wi-Fi shows the same connection-lost notice as a failed probe.
        if let key = input.recoveryNoticeKey ?? (input.isWiFiConnected ? nil : "recovery.connectionLost"),
           !notices.isDismissed(.recovery), !teleportFailureOwns {
            result.append(.connection(key: key, coldConfirmation: input.requiresColdConfirmation))
        }
        if let resume = resumeNotice(input, teleportFailureOwns: teleportFailureOwns) {
            result.append(.resume(resume))
        }
        return result
    }

    private static func resumeNotice(_ input: MapNoticeInputs, teleportFailureOwns: Bool) -> MapNotice.ResumeNotice? {
        let active = input.activeMovement
        // The person pressed Pause: the resume panel already says so.
        let pausedByUser = active?.isPausedByUser == true
            && ((input.mode == .route && active?.kind == .route) || (input.mode == .joystick && active?.kind == .wander))
        let continuationShown = input.continuationNoticeKey != nil && !input.notices.isDismissed(.continuation)
        guard input.sceneSettled, !input.repairOwnsNotice, !teleportFailureOwns, !pausedByUser,
              continuationShown || input.isResumeState else { return nil }

        let resumable = active?.resumeAction
        let routePaused = input.mode == .route && (resumable == .resumeRoute || resumable == .retryInterruptedRoute)
        let holdPaused = resumable == .retryPositionHold
        let wanderPaused = input.mode == .joystick && resumable == .resumeWander
        let action = routePaused || holdPaused || wanderPaused ? resumable : nil
        let titleKey = routePaused ? "route.pausedToast.title"
            : holdPaused ? "background.positionPaused"
            : wanderPaused ? "joystick.wanderPaused"
            : input.continuationNoticeKey ?? "background.positionPaused"
        let messageKey = routePaused ? "route.pausedToast.message"
            : holdPaused ? "background.positionPaused.message" : "status.repairGuidance"
        return MapNotice.ResumeNotice(titleKey: titleKey, messageKey: messageKey,
                                      actionTitleKey: routePaused || holdPaused ? "common.continue" : "common.retry",
                                      action: action,
                                      actionEnabled: action == nil || active?.canResume == true)
    }
}
