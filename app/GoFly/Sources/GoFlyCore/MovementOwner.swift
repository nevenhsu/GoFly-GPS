import Foundation

/// What connection recovery and background continuation need from the route,
/// joystick/wander and position-hold owners. Each owner answers from its own
/// phase and lease, so neither caller reads another module's internals.
@MainActor
protocol MovementOwner: AnyObject {
    /// The running movement's execution ID, if any.
    var movementID: UUID? { get }
    var isRecoveringConnection: Bool { get }
    /// Stops writing while the service repairs the connection; false when not running.
    func suspendForConnectionRecovery() -> Bool
    func finishConnectionRecovery(succeeded: Bool)
    func isContinuationReady(movementID: UUID, lease: MovementTaskLease) -> Bool
}

extension RouteExecutionController: MovementOwner {
    var movementID: UUID? { intent?.id }
    func isContinuationReady(movementID: UUID, lease: MovementTaskLease) -> Bool {
        phase == .running && intent?.id == movementID && intent?.lease == lease
    }
}

extension JoystickMovementController: MovementOwner {
    var movementID: UUID? { intent?.id }
    /// The service emits a wander's first accepted ACK before this owner's
    /// async return; the installed healthy owner is already real.
    func isContinuationReady(movementID: UUID, lease: MovementTaskLease) -> Bool {
        [.preparing, .moving].contains(phase) && wanderEnabled && intent?.id == movementID && intent?.lease == lease
    }
}

extension PositionHoldController: MovementOwner {
    var movementID: UUID? { intent?.id }
    func isContinuationReady(movementID: UUID, lease: MovementTaskLease) -> Bool {
        phase == .running && intent?.id == movementID && intent?.lease == lease
    }
}
