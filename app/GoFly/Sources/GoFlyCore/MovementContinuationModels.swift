import Combine
import Foundation

public enum MovementAcknowledgementSource: Equatable, Sendable {
    case route
    case joystick
    case fixedPosition
}

/// An acknowledgement emitted only after a native command has crossed its
/// current owner gate and the service has accepted its result.
public struct MovementAcknowledgement: Equatable, Sendable {
    public let movementID: UUID
    public let lease: MovementTaskLease
    public let sequence: UInt64
    public let source: MovementAcknowledgementSource
    public let acknowledgedDistanceMeters: Double
    public let cumulativeAcknowledgedDurationSeconds: Double
    public let routePositionMeters: Double?
    public let finiteArrival: Bool

    init(movementID: UUID, lease: MovementTaskLease, sequence: UInt64,
         source: MovementAcknowledgementSource, acknowledgedDistanceMeters: Double,
         routePositionMeters: Double? = nil, finiteArrival: Bool = false,
         cumulativeAcknowledgedDurationSeconds: Double = 0) {
        self.movementID = movementID
        self.lease = lease
        self.sequence = sequence
        self.source = source
        self.acknowledgedDistanceMeters = acknowledgedDistanceMeters
        self.cumulativeAcknowledgedDurationSeconds = cumulativeAcknowledgedDurationSeconds
        self.routePositionMeters = routePositionMeters
        self.finiteArrival = finiteArrival
    }
}

public struct TeleportAcknowledgement: Equatable, Sendable {
    public let intent: PointMoveIntent
    public let lease: MovementTaskLease
    public let displayEpoch: UUID
    public let admissionRevision: UInt64

    init(intent: PointMoveIntent, lease: MovementTaskLease, displayEpoch: UUID,
         admissionRevision: UInt64) {
        self.intent = intent
        self.lease = lease
        self.displayEpoch = displayEpoch
        self.admissionRevision = admissionRevision
    }

    public var coordinate: GeoCoordinate { intent.candidate.place.coordinate }
}

public struct MovementContinuationDemand: Equatable, Sendable {
    public let movementID: UUID
    public let lease: MovementTaskLease
    public let kind: ContinuedProcessingKind
    public let goal: ContinuedProcessingGoal?
    /// Finite routes only: the route-axis endpoint the trip departs from
    /// (0 forward, total distance in reverse). Background progress is the
    /// distance covered from it, so it always tracks the whole route.
    public let routeAxisOrigin: Double?

    init(movementID: UUID, lease: MovementTaskLease, kind: ContinuedProcessingKind,
         goal: ContinuedProcessingGoal?, routeAxisOrigin: Double? = nil) {
        self.movementID = movementID
        self.lease = lease
        self.kind = kind
        self.goal = goal
        self.routeAxisOrigin = routeAxisOrigin
    }
}

public struct MovementContinuationIdentity: Equatable, Sendable {
    public let movementID: UUID
    public let lease: MovementTaskLease

    public init(movementID: UUID, lease: MovementTaskLease) {
        self.movementID = movementID
        self.lease = lease
    }
}

public enum MovementContinuationWithdrawalReason: Equatable, Sendable {
    case userPaused
    case userCancelled
    case automaticDisabled(manualInputContinues: Bool)
    case ended
}

extension MovementContinuationWithdrawalReason {
    public var diagnosticsLabel: String {
        switch self {
        case .userPaused: "userPaused"
        case .userCancelled: "userCancelled"
        case .automaticDisabled(let manualInputContinues): manualInputContinues ? "automaticDisabled.manual" : "automaticDisabled"
        case .ended: "ended"
        }
    }
}

public enum MovementContinuationControlEvent: Sendable {
    case requested(MovementContinuationDemand)
    case withdrawn(MovementContinuationIdentity, MovementContinuationWithdrawalReason)
}

public enum MovementContinuationRetirement: Equatable, Sendable {
    case ownerPausedOrEnded
    case foregroundGoalChange
    case foregroundManualAfterAutoOff

    public var diagnosticsLabel: String {
        switch self {
        case .ownerPausedOrEnded: "ownerPausedOrEnded"
        case .foregroundGoalChange: "foregroundGoalChange"
        case .foregroundManualAfterAutoOff: "foregroundManualAfterAutoOff"
        }
    }
}
