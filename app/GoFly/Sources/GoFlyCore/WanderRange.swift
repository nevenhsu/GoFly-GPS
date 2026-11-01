import Combine
import Foundation

/// Wander radius preference (Figma E2.b): 0.1–100 km in 0.1 km steps, default 5 km.
public struct WanderRadius: Equatable, Sendable {
    public static let minimumKilometers = 0.1
    public static let maximumKilometers = 100.0
    public static let `default` = WanderRadius(kilometers: 5)

    public let kilometers: Double
    public var meters: Double { kilometers * 1000 }

    /// Clamps to the supported range; a non-finite value falls back to the default.
    public init(kilometers: Double) {
        guard kilometers.isFinite else { self.kilometers = 5; return }
        let stepped = (kilometers * 10).rounded() / 10
        self.kilometers = min(max(stepped, Self.minimumKilometers), Self.maximumKilometers)
    }
}

/// The circle automatic wander targets must stay inside.
public struct WanderRange: Equatable, Sendable {
    public let anchor: GeoCoordinate
    public let radiusMeters: Double
    public init(anchor: GeoCoordinate, radiusMeters: Double) {
        self.anchor = anchor; self.radiusMeters = radiusMeters
    }
    public func contains(_ coordinate: GeoCoordinate) -> Bool {
        JoystickGeodesy.distanceMeters(from: anchor, to: coordinate) <= radiusMeters
    }
}

/// Owns the wander range shown on the joystick and wander map. The anchor
/// only moves when the person teleports (map pin) while no wander runs; joystick
/// movement and a running wander never move it. Destinations the person picks
/// are not limited by the range, only automatically selected ones are.
@MainActor
public final class WanderRangeController: ObservableObject {
    @Published public private(set) var radius: WanderRadius
    /// Whether the range circle is drawn. It never changes the range itself.
    @Published public private(set) var isVisible: Bool
    @Published public private(set) var anchor: GeoCoordinate?
    /// Reports the persisted part of the range; the anchor is session-only.
    private let onChange: @MainActor (WanderRadius, Bool) -> Void

    public init(radius: WanderRadius = .default, isVisible: Bool = true, anchor: GeoCoordinate? = nil,
                onChange: @escaping @MainActor (WanderRadius, Bool) -> Void = { _, _ in }) {
        self.radius = radius; self.isVisible = isVisible; self.anchor = anchor; self.onChange = onChange
    }

    public func setRadius(_ value: WanderRadius) {
        guard radius != value else { return }
        radius = value
        onChange(radius, isVisible)
    }

    public func setVisible(_ value: Bool) {
        guard isVisible != value else { return }
        isVisible = value
        onChange(radius, isVisible)
    }

    /// A teleport was acknowledged. Only one made while no wander runs re-centres the range.
    public func teleportAcknowledged(at coordinate: GeoCoordinate, wanderRunning: Bool) {
        guard !wanderRunning, anchor != coordinate else { return }
        anchor = coordinate
    }

    /// A new automatic wander starts at `origin`. When that is outside the current range (a
    /// route or relaunch moved the position since), the range is re-centred there, so the
    /// wander never plans a long trip back to an old circle.
    public func wanderStarting(at origin: GeoCoordinate) {
        guard let anchor else { adoptAnchorIfNeeded(origin); return }
        guard !WanderRange(anchor: anchor, radiusMeters: radius.meters).contains(origin) else { return }
        self.anchor = origin
    }

    /// Fixes the anchor at the first known position; a later position never moves it.
    public func adoptAnchorIfNeeded(_ coordinate: GeoCoordinate) {
        guard anchor == nil else { return }
        anchor = coordinate
    }

    /// The range automatic selection uses. Without an anchor yet, the first
    /// wander origin becomes it.
    public func range(origin: GeoCoordinate) -> WanderRange {
        adoptAnchorIfNeeded(origin)
        return WanderRange(anchor: anchor ?? origin, radiusMeters: radius.meters)
    }
}
