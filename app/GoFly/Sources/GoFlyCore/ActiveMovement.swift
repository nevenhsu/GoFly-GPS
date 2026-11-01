import Foundation

/// The one movement GoFly is advancing or holding on the device right now,
/// independent of the tab the person is looking at. Every "is something
/// running or paused, and why" question reads this single derivation.
public struct ActiveMovement: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case route, joystick, wander, positionHold
    }

    public enum RunState: String, Equatable, Sendable {
        /// Planning, preparing, pausing, settling or cancelling: neither running nor paused.
        case transitioning
        case running
        /// A running wander finished its segment and plans the next one.
        case awaitingTarget
        case paused
        /// The connection failed and the movement waits for a repair.
        case interrupted
        /// A write's outcome is unknown; only Stop resolves it.
        case unknown
        /// A position hold reached its run time.
        case completed
    }

    public enum PauseCause: String, Equatable, Sendable {
        /// The person pressed Pause.
        case user
        case connection
        /// The scene left the foreground without a valid background runtime, or it expired.
        case background
    }

    /// The command that continues this movement from the resume notice.
    public enum ResumeAction: Equatable, Sendable {
        case resumeRoute, retryInterruptedRoute, resumeWander, retryPositionHold
    }

    public let kind: Kind
    public let runState: RunState
    /// Set only while `runState` is `.paused` or `.interrupted`.
    public let pauseCause: PauseCause?
    public let resumeAction: ResumeAction?
    /// Whether `resumeAction` is admitted right now.
    public let canResume: Bool

    public init(kind: Kind, runState: RunState, pauseCause: PauseCause? = nil,
                resumeAction: ResumeAction? = nil, canResume: Bool = false) {
        self.kind = kind; self.runState = runState; self.pauseCause = pauseCause
        self.resumeAction = resumeAction; self.canResume = canResume
    }

    /// Counts as running for the status pill.
    public var isRunning: Bool { runState == .running || runState == .awaitingTarget }
    /// Counts as paused for the status pill.
    public var isPaused: Bool { [.paused, .interrupted, .unknown].contains(runState) }
    /// Stopped short of its goal with a resume action: the person can continue it.
    public var isResumable: Bool { resumeAction != nil && (runState == .paused || runState == .interrupted) }
    public var isPausedByUser: Bool { runState == .paused && pauseCause == .user }

    public var diagnosticsLabel: String {
        "\(kind.rawValue).\(runState.rawValue)" + (pauseCause.map { ".\($0.rawValue)" } ?? "")
    }
}

extension ActiveMovement {
    /// Route first, then joystick or wander, then the position hold: a new
    /// route or joystick owner always replaces a hold before it runs.
    @MainActor
    public init?(route: RouteExecutionController, joystick: JoystickMovementController,
                 positionHold: PositionHoldController?) {
        if let movement = Self.route(route) ?? Self.joystick(joystick) ?? positionHold.flatMap(Self.positionHold) {
            self = movement
        } else {
            return nil
        }
    }

    @MainActor
    private static func route(_ route: RouteExecutionController) -> ActiveMovement? {
        switch route.phase {
        case .editing: return nil
        case .planning, .preparing, .pausing, .cancelling: return ActiveMovement(kind: .route, runState: .transitioning)
        case .running: return ActiveMovement(kind: .route, runState: .running)
        case .paused:
            let cause: PauseCause = switch route.suspensionReason {
            case nil: .user
            case .connectionUnavailable: .connection
            case .sceneInactive, .backgroundUnavailable: .background
            }
            return ActiveMovement(kind: .route, runState: .paused, pauseCause: cause,
                                  resumeAction: .resumeRoute, canResume: route.canResume)
        case .interrupted:
            return ActiveMovement(kind: .route, runState: .interrupted, pauseCause: .connection,
                                  resumeAction: .retryInterruptedRoute, canResume: true)
        case .unknown: return ActiveMovement(kind: .route, runState: .unknown)
        }
    }

    @MainActor
    private static func joystick(_ joystick: JoystickMovementController) -> ActiveMovement? {
        let wander = joystick.wanderEnabled
        let kind: Kind = wander ? .wander : .joystick
        let resume: ResumeAction? = wander ? .resumeWander : nil
        switch joystick.phase {
        case .neutral: return wander ? ActiveMovement(kind: kind, runState: .transitioning) : nil
        case .preparing, .settling, .pausing: return ActiveMovement(kind: kind, runState: .transitioning)
        case .moving: return ActiveMovement(kind: kind, runState: .running)
        case .paused, .suspended:
            if joystick.isAwaitingNextTarget { return ActiveMovement(kind: kind, runState: .awaitingTarget) }
            let cause: PauseCause = switch joystick.suspensionReason {
            case nil, .targetUnavailable: .user
            case .connectionUnavailable: .connection
            case .sceneInactive, .backgroundUnavailable: .background
            }
            return ActiveMovement(kind: kind, runState: .paused, pauseCause: cause,
                                  resumeAction: resume, canResume: resume != nil)
        case .interrupted:
            return ActiveMovement(kind: kind, runState: .interrupted, pauseCause: .connection,
                                  resumeAction: resume, canResume: resume != nil)
        case .unknown: return ActiveMovement(kind: kind, runState: .unknown)
        }
    }

    @MainActor
    private static func positionHold(_ hold: PositionHoldController) -> ActiveMovement? {
        switch hold.phase {
        case .idle: return nil
        case .preparing: return ActiveMovement(kind: .positionHold, runState: .transitioning)
        case .running: return ActiveMovement(kind: .positionHold, runState: .running)
        case .paused:
            return ActiveMovement(kind: .positionHold, runState: .paused, pauseCause: hold.pauseCause ?? .connection,
                                  resumeAction: .retryPositionHold, canResume: hold.canRetry)
        case .unknown: return ActiveMovement(kind: .positionHold, runState: .unknown)
        case .completed:
            return ActiveMovement(kind: .positionHold, runState: .completed,
                                  resumeAction: .retryPositionHold, canResume: hold.canRetry)
        }
    }
}
