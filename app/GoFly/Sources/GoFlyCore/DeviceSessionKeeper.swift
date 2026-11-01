import Foundation

/// The native handles behind one device session. The adapter owns them and
/// calls the keeper only on its own serial queue; nothing here is thread-safe.
public protocol DeviceSessionLink: AnyObject {
    /// Whether a native session is currently installed, prepared or not.
    var ownsSession: Bool { get }
    /// Reuses the installed session or opens one, then runs full preparation.
    /// A session opened here stays installed (unprepared) when preparation fails.
    func prepareSession() throws
    /// One point write. Reuses or opens a session, prepares it only when
    /// needed, then claims the gate (`recovering` uses the recovery claim).
    /// A session opened here stays installed whatever the outcome.
    func attemptPoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate,
                      recovering: Bool, deadline: UInt64) -> DeviceSessionAttempt
    /// Closes and forgets the installed session, if any, without clearing.
    func closeSession()
}

public struct DeviceSessionAttempt: Equatable, Sendable {
    public let outcome: PointDeliveryOutcome
    /// False when the attempt failed while opening or preparing the session.
    public let reachedDispatch: Bool

    public init(outcome: PointDeliveryOutcome, reachedDispatch: Bool) {
        self.outcome = outcome
        self.reachedDispatch = reachedDispatch
    }
}

/// Decides when a native session is reused, rebuilt or closed for idleness. Every point write goes through `deliver`; the adapter only
/// performs single attempts and never retries on its own.
///
/// While the device may hold a simulated position the session is never closed
/// for idleness: closing the location channel can return the device to real
/// GPS, and only an explicit clear may do that. The keeper never reconnects
/// or retries a write by itself: automatic repair belongs to
/// `ConnectionRecoveryController`, at most once per 60 seconds per task (ADR 0001).
public final class DeviceSessionKeeper {
    public static let defaultMaximumIdleNanoseconds: UInt64 = 30_000_000_000
    /// The deadline of one write attempt. It is deliberately shorter than the
    /// outer service watchdog so an adapter timeout can still return cleanly.
    public static let defaultPointBudgetNanoseconds: UInt64 = 20_000_000_000

    private let maximumIdleNanoseconds: UInt64
    private let pointBudgetNanoseconds: UInt64
    private let now: () -> UInt64
    private var lastActivityAt: UInt64?
    /// True from any write that may have reached the device until a clear is
    /// acknowledged.
    public private(set) var mayHoldSimulatedPosition = false

    public init(maximumIdleNanoseconds: UInt64 = defaultMaximumIdleNanoseconds,
                pointBudgetNanoseconds: UInt64 = defaultPointBudgetNanoseconds,
                now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.maximumIdleNanoseconds = maximumIdleNanoseconds
        self.pointBudgetNanoseconds = pointBudgetNanoseconds
        self.now = now
    }

    public func prepare(using link: any DeviceSessionLink) throws {
        discardIfIdle(link)
        let wasOwned = link.ownsSession
        do {
            try link.prepareSession()
            lastActivityAt = now()
        } catch {
            let failure = error as? DeviceServiceFailure ?? .serviceUnavailable
            if shouldRebuild(after: failure, sessionWasOwned: wasOwned) { close(link) }
            throw failure
        }
    }

    /// Shared by teleport, route, and joystick/wander movement. One attempt,
    /// no retry: a transient failure closes the session and is returned, and
    /// the recovery controller decides about the single automatic repair.
    public func deliver(_ coordinate: GeoCoordinate, dispatch: PointDispatchGate,
                        using link: any DeviceSessionLink) -> PointDeliveryOutcome {
        attempt(coordinate, dispatch: dispatch, deadline: now() &+ pointBudgetNanoseconds, link: link)
    }

    /// The adapter closed the session itself (clear, rebuild).
    public func sessionDidClose() {
        lastActivityAt = nil
    }

    /// The device acknowledged a clear; it now reports real GPS.
    public func locationDidClear() {
        mayHoldSimulatedPosition = false
    }

    private func attempt(_ coordinate: GeoCoordinate, dispatch: PointDispatchGate,
                         deadline: UInt64, link: any DeviceSessionLink) -> PointDeliveryOutcome {
        guard case .available = dispatch.state else { return .notSent(.operationCancelled) }
        discardIfIdle(link)
        let wasOwned = link.ownsSession
        let result = link.attemptPoint(to: coordinate, dispatch: dispatch,
                                       recovering: false, deadline: deadline)
        if result.reachedDispatch, dispatch.hasDispatched { mayHoldSimulatedPosition = true }
        if shouldRebuild(after: result.outcome, sessionWasOwned: wasOwned) {
            close(link)
        } else if result.reachedDispatch {
            lastActivityAt = now()
        }
        return result.outcome
    }

    private func discardIfIdle(_ link: any DeviceSessionLink) {
        guard link.ownsSession, !mayHoldSimulatedPosition, maximumIdleNanoseconds > 0,
              let lastActivityAt else { return }
        let current = now()
        guard current >= lastActivityAt, current - lastActivityAt >= maximumIdleNanoseconds else { return }
        Diagnostics.shared.record("device.session.repair", category: .device, level: .notice, [
            "reason": .text("idle"),
            "idle_ms": .milliseconds(Double(maximumIdleNanoseconds / 1_000_000))
        ])
        close(link)
    }

    private func close(_ link: any DeviceSessionLink) {
        link.closeSession()
        lastActivityAt = nil
    }

    private func shouldRebuild(after outcome: PointDeliveryOutcome, sessionWasOwned: Bool) -> Bool {
        switch outcome {
        case .acknowledged:
            return false
        case .unconfirmed(let failure):
            return Self.isTransient(failure)
        case .notSent(let failure):
            return shouldRebuild(after: failure, sessionWasOwned: sessionWasOwned)
        }
    }

    /// A session this attempt opened is never kept after a failure; an owned
    /// one is replaced only after a known transport or service failure.
    private func shouldRebuild(after failure: DeviceServiceFailure, sessionWasOwned: Bool) -> Bool {
        guard sessionWasOwned else { return true }
        return Self.isTransient(failure)
    }

    /// The only failures that justify a fresh RSD connection.
    static func isTransient(_ failure: DeviceServiceFailure) -> Bool {
        switch failure {
        case .serviceUnavailable, .tunnelUnavailable, .operationTimedOut:
            return true
        case .pairingRequired, .identityMismatch, .developerModeRequired,
             .devicePreparationRequired, .deviceRequired, .storageUnavailable,
             .operationCancelled:
            return false
        }
    }
}
