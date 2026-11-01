import Foundation

/// Shared by all movement modes and both session pills. Probe progress is
/// deliberately independent of the last completed connectivity result.
public enum SessionDisplayStatus: Equatable, Sendable {
    case started, connecting, simulating, paused, stopped, error

    /// `connecting` is the movement permission (tunnel) still being
    /// established; it yields to any real error.
    public init(hasError: Bool, connecting: Bool = false, running: Bool, paused: Bool, hasSimulated: Bool) {
        if hasError { self = .error }
        else if connecting { self = .connecting }
        else if running { self = .simulating }
        else if paused { self = .paused }
        else { self = hasSimulated ? .stopped : .started }
    }

    public var textKey: String {
        switch self {
        case .started: "status.pill.started"
        case .connecting: "status.pill.connecting"
        case .simulating: "status.pill.simulating"
        case .paused: "status.pill.paused"
        case .stopped: "status.pill.stopped"
        case .error: "status.pill.error"
        }
    }
}

public struct MovementConnectionRecovery: Equatable, Sendable {
    public let id: UUID
    public let executionID: UUID
    public let lease: MovementTaskLease
    public let coordinate: GeoCoordinate
    public let failure: DeviceServiceFailure
    public let resumesTask: Bool
    /// A user Retry is explicit. An automatic request (false) is the one silent
    /// repair attempt per task lease, made after the device keeper's own
    /// reconnect failed or ran out of budget; a failure then waits for Retry.
    public let explicitlyRequested: Bool
}

/// Concrete error messages behind the shared Error pill. Dismissing a toast
/// does not clear its underlying error; successful normal operations do.
public struct SessionStatusErrors: Equatable, Sendable {
    public let keys: [String]
    public var isEmpty: Bool { keys.isEmpty }

    /// A cancellation is the app ending its own superseded work, not a fault:
    /// neither the pill nor a toast reports it.
    public static func reportsFailure(_ key: String) -> Bool {
        key != DeviceServiceFailure.operationCancelled.rawValue
    }

    public init(connection: VPNCheckState, service: DeviceServiceFailure? = nil,
                route: RouteExecutionFailure? = nil, joystick: JoystickFailure? = nil,
                wander: WanderSelectionFailure? = nil,
                dataErrors: [String] = []) {
        var messages: [String] = []
        switch connection {
        case .unavailable: messages.append(DeviceServiceFailure.tunnelUnavailable.rawValue)
        case .timedOut: messages.append(DeviceServiceFailure.operationTimedOut.rawValue)
        case .unknown, .checking, .reachable: break
        }
        messages += [service?.rawValue, route?.localizationKey, joystick?.localizationKey,
                     wander?.localizationKey].compactMap { $0 }
        messages += dataErrors
        var seen: Set<String> = []
        keys = messages.filter {
            // D8 presents failed route planning in its floating page toast;
            // Figma keeps the shared session pill at Started for this case.
            $0 != RouteExecutionFailure.planningFailed.localizationKey
                && Self.reportsFailure($0) && !IssueCatalog.isValidation($0)
                && seen.insert($0).inserted
        }
    }
}
