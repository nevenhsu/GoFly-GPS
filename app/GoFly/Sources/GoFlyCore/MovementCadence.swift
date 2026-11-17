import Foundation

/// How often each writer sends a point (2026-10-25). Manual joystick control
/// stays responsive at half a second; route and wander send once a second and
/// the map arrow predicts along the path from the
/// acknowledged points (2026-11-17). In the background
/// (2026-11-17) route and wander send every 2 seconds with a step twice as
/// long, so the average speed is unchanged while writes are halved.
public enum MovementCadence {
    public static let manualSeconds = 0.5
    public static let pathSeconds = 1.0
    public static let backgroundPathSeconds = 2.0
    public static let manual: Duration = .milliseconds(500)
    public static let path: Duration = .seconds(1)
    public static let backgroundPath: Duration = .seconds(2)
    /// Route cadences are injectable; the background stretches them by this factor.
    public static let backgroundPathFactor = 2
}
