import Foundation

public enum ContinuedProcessingKind: String, CaseIterable, Equatable, Sendable {
    case finiteRoute
    case fixedPosition
    case roundTrip
    case wander
}

public enum ContinuedProcessingGoal: Equatable, Sendable {
    case finiteDistance(meters: Double)
    case finiteDuration(seconds: Double)
    case experimentalIndeterminate
}

public struct ContinuedProcessingRequest: Equatable, Sendable {
    public let requestID: UUID
    public let movementID: UUID
    public let lease: MovementTaskLease
    public let kind: ContinuedProcessingKind
    public let goal: ContinuedProcessingGoal
    public let title: String
    public let subtitle: String

    public init?(requestID: UUID = UUID(), movementID: UUID, lease: MovementTaskLease,
                 kind: ContinuedProcessingKind, goal: ContinuedProcessingGoal,
                 title: String, subtitle: String) {
        guard Self.isValidPresentation(title, maximumUTF8Bytes: 128),
              Self.isValidPresentation(subtitle, maximumUTF8Bytes: 512),
              Self.isValid(kind: kind, goal: goal) else { return nil }
        self.requestID = requestID
        self.movementID = movementID
        self.lease = lease
        self.kind = kind
        self.goal = goal
        self.title = title
        self.subtitle = subtitle
    }

    static func isValidPresentation(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumUTF8Bytes else { return false }
        return !value.unicodeScalars.contains { $0.value == 0 }
    }

    static func isValid(kind: ContinuedProcessingKind, goal: ContinuedProcessingGoal) -> Bool {
        switch (kind, goal) {
        case (.finiteRoute, .finiteDistance(let meters)):
            return meters.isFinite && meters > 0
        case (.finiteRoute, .experimentalIndeterminate):
            return false
        case (.fixedPosition, .finiteDuration(let seconds)):
            return seconds.isFinite && seconds > 0 && seconds <= BackgroundRunDuration.maximumSeconds
        case (.roundTrip, .finiteDuration(let seconds)):
            return seconds.isFinite && seconds > 0 && seconds <= BackgroundRunDuration.maximumSeconds
        case (.wander, .finiteDuration(let seconds)):
            return seconds.isFinite && seconds > 0 && seconds <= BackgroundRunDuration.maximumSeconds
        case (.fixedPosition, .finiteDistance), (.fixedPosition, .experimentalIndeterminate):
            return false
        case (.roundTrip, .experimentalIndeterminate), (.wander, .experimentalIndeterminate):
            return true
        case (.roundTrip, .finiteDistance), (.wander, .finiteDistance),
             (.finiteRoute, .finiteDuration):
            return false
        }
    }
}

public struct ContinuedProcessingProgress: Equatable, Sendable {
    public let acknowledgedWrites: Int64
    public let cumulativeAcknowledgedDistanceMeters: Double
    public let cumulativeAcknowledgedDurationSeconds: Double

    public init?(acknowledgedWrites: Int64, cumulativeAcknowledgedDistanceMeters: Double,
                cumulativeAcknowledgedDurationSeconds: Double = 0) {
        guard acknowledgedWrites >= 0,
              cumulativeAcknowledgedDistanceMeters.isFinite,
              cumulativeAcknowledgedDistanceMeters >= 0,
              cumulativeAcknowledgedDurationSeconds.isFinite,
              cumulativeAcknowledgedDurationSeconds >= 0 else { return nil }
        self.acknowledgedWrites = acknowledgedWrites
        self.cumulativeAcknowledgedDistanceMeters = cumulativeAcknowledgedDistanceMeters
        self.cumulativeAcknowledgedDurationSeconds = cumulativeAcknowledgedDurationSeconds
    }

    public static let zero = ContinuedProcessingProgress(acknowledgedWrites: 0,
                                                          cumulativeAcknowledgedDistanceMeters: 0,
                                                          cumulativeAcknowledgedDurationSeconds: 0)!
}

/// Unit counts sent to the system continued-processing progress object.
///
/// Finite duration and distance goals use the same bounded percentage scale
/// understood by the system continued-processing progress object.
public struct ContinuedProcessingProgressUnits: Equatable, Sendable {
    public let totalUnitCount: Int64
    public let completedUnitCount: Int64

    public init(totalUnitCount: Int64, completedUnitCount: Int64) {
        self.totalUnitCount = totalUnitCount
        self.completedUnitCount = completedUnitCount
    }

    public static func forRequest(_ request: ContinuedProcessingRequest,
                                  progress: ContinuedProcessingProgress) -> Self {
        switch request.goal {
        case .finiteDistance(let goal) where goal.isFinite && goal > 0:
            let ratio = min(max(progress.cumulativeAcknowledgedDistanceMeters / goal, 0), 1)
            let completed = safeInt64Floor(ratio * 1_000_000, cap: 999_999)
            return Self(totalUnitCount: 1_000_000, completedUnitCount: completed)
        case .finiteDuration(let goal) where goal.isFinite && goal > 0:
            let ratio = min(max(progress.cumulativeAcknowledgedDurationSeconds / goal, 0), 1)
            let completed = safeInt64Floor(ratio * 1_000_000, cap: 999_999)
            return Self(totalUnitCount: 1_000_000, completedUnitCount: completed)
        case .experimentalIndeterminate:
            return Self(totalUnitCount: -1, completedUnitCount: progress.acknowledgedWrites)
        default:
            return Self(totalUnitCount: -1, completedUnitCount: progress.acknowledgedWrites)
        }
    }

    private static func safeInt64Floor(_ value: Double, cap: Int64) -> Int64 {
        guard value.isFinite, value >= 0 else { return value.sign == .minus ? 0 : cap }
        let conversionLimit = Double(Int64.max) - 1_000_000
        guard value < conversionLimit else { return cap }
        return min(Int64(floor(value)), cap)
    }
}

public enum ContinuedProcessingFailure: Error, Equatable, Sendable {
    case unsupportedSystem
    case registrationFailed
    case registrationLimitReached
    case notForeground
    case submissionRejected
    case cancelled
    case invalidProgress
}

public enum ContinuedProcessingState: Equatable, Sendable {
    case idle
    case submitting
    case accepted
    case running
    case rejected
    case expired
    case finished
}

public enum ContinuedProcessingRuntimeLoss: Equatable, Sendable {
    case expired
    case invalidated
    case submissionRejected
    case cancelled
    case superseded
}

public enum ContinuedProcessingEvent: Sendable {
    case launched(ContinuedProcessingGrant)
    case expired(requestID: UUID)
    case invalidated(requestID: UUID)
}

public enum ContinuedProcessingCompletionOutcome: String, Equatable, Sendable {
    case success
    case expired
    case cancelled
    case invalidated
    case failed
}

public struct ContinuedProcessingCompletionClaim: Equatable, Sendable {
    public let outcome: ContinuedProcessingCompletionOutcome
    public let isFirst: Bool

    init(outcome: ContinuedProcessingCompletionOutcome, isFirst: Bool) {
        self.outcome = outcome
        self.isFirst = isFirst
    }
}

public enum ContinuedProcessingReceiptEvent: Equatable, Sendable {
    case submitted
    case accepted
    case launched
    case rejected(ContinuedProcessingFailure)
    case expired
    case invalidated
    case cancelRequested
    case superseded
    case progressUpdated
    case completionRequested(ContinuedProcessingCompletionOutcome?)
}

public struct ContinuedProcessingReceipt: Equatable, Sendable {
    public let timestamp: Date
    public let requestID: UUID
    public let kind: ContinuedProcessingKind
    public let event: ContinuedProcessingReceiptEvent
    public let acknowledgedWrites: Int64
    public let cumulativeAcknowledgedDistanceMeters: Double
    public let cumulativeAcknowledgedDurationSeconds: Double
    public let candidateVersion: Int

    init(timestamp: Date, requestID: UUID, kind: ContinuedProcessingKind,
         event: ContinuedProcessingReceiptEvent, progress: ContinuedProcessingProgress,
         candidateVersion: Int = 1) {
        self.timestamp = timestamp
        self.requestID = requestID
        self.kind = kind
        self.event = event
        self.acknowledgedWrites = progress.acknowledgedWrites
        self.cumulativeAcknowledgedDistanceMeters = progress.cumulativeAcknowledgedDistanceMeters
        self.cumulativeAcknowledgedDurationSeconds = progress.cumulativeAcknowledgedDurationSeconds
        self.candidateVersion = candidateVersion
    }
}

@MainActor
public protocol ContinuedProcessingDriving: AnyObject {
    func register() -> Bool
    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws
    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String)
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome?
    func cancel(requestID: UUID)
}

/// How long a background-continued movement (fixed position, round trip, wander)
/// may run. The user adjusts it in Settings; from 1 minute to 24 hours 59 minutes (default 1 hour).
public final class BackgroundRunDuration: @unchecked Sendable {
    public static let shared = BackgroundRunDuration()
    public static let maximumSeconds: TimeInterval = 89_940
    public static let minimumSeconds: TimeInterval = 60
    public static let defaultSeconds: TimeInterval = 3_600

    private let lock = NSLock()
    private var stored = BackgroundRunDuration.defaultSeconds

    public var seconds: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set {
            let clamped = Self.clamp(newValue)
            lock.lock(); stored = clamped; lock.unlock()
        }
    }

    public static func clamp(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultSeconds }
        return min(maximumSeconds, max(minimumSeconds, value.rounded()))
    }
}
