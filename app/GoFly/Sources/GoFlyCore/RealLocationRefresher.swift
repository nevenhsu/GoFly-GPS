import Foundation

/// Asks the platform for one low-power real location fix.
@MainActor
public protocol RealLocationFixRequesting: AnyObject {
    func requestFix()
}

/// Keeps the real location fresh enough for joystick and route origins, which
/// accept a fix up to 15 s old, with occasional one-shot fixes instead of a
/// continuous GPS stream. It refreshes only while the scene is active and the
/// device reports its real location. A software-simulated fix normally stops
/// polling, except during a bounded wait for real GPS after a clear or recenter.
@MainActor
public final class RealLocationRefresher {
    public static let interval: Duration = .seconds(8)
    public static let realFixWaitSeconds: TimeInterval = 30

    private weak var source: (any RealLocationFixRequesting)?
    private let clock: any RouteClock
    private let interval: Duration
    private var sceneActive = false
    private var task: Task<Void, Never>?
    private var retrySimulatedUntil: Duration?

    /// The last fix was software-simulated.
    public private(set) var deviceSimulating = false
    public var isRefreshing: Bool { task != nil }

    public init(source: any RealLocationFixRequesting, clock: any RouteClock = ContinuousRouteClock(),
                interval: Duration = RealLocationRefresher.interval) {
        self.source = source; self.clock = clock; self.interval = interval
    }

    /// Something needs a current fix now: Recenter, a joystick origin, or a
    /// confirmed GPS clear. It retries real GPS even after a simulated fix.
    public func refreshNow(waitingForRealFix: Bool = false) {
        if waitingForRealFix {
            retrySimulatedUntil = clock.now + .seconds(Self.realFixWaitSeconds)
        }
        deviceSimulating = false
        stop()
        if sceneActive { startLoop() } else { source?.requestFix() }
    }

    public func sceneDidBecomeActive() {
        sceneActive = true
        refreshNow()
    }

    public func sceneDidBecomeInactive() {
        sceneActive = false
        stop()
    }

    public func fixReceived(simulated: Bool) {
        deviceSimulating = simulated
        if simulated {
            if !canRetrySimulatedFix { stop() }
        } else if sceneActive, task == nil {
            startLoop()
        }
    }

    private var canRetrySimulatedFix: Bool {
        guard let deadline = retrySimulatedUntil else { return false }
        return clock.now < deadline
    }

    private func startLoop() {
        let clock = clock, interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.requestNextFix() == true else { return }
                do { try await clock.sleep(for: interval) } catch { return }
            }
        }
    }

    private func requestNextFix() -> Bool {
        if deviceSimulating, !canRetrySimulatedFix {
            stop()
            return false
        }
        source?.requestFix()
        return true
    }

    private func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
