import Foundation

public enum WanderTargetSelector {
    /// Picks one random direction on the ten-minute ring, capped by the wander
    /// range radius. With a range, only a candidate inside it is accepted; when
    /// no sampled bearing fits (the origin sits outside or on the edge of the
    /// range), the target falls back to a point inside the range around its
    /// anchor so the wander heads back.
    public static func select(origin: GeoCoordinate, speed: RouteSpeed,
                              bearingSamples: [Double], range: WanderRange? = nil) -> WanderTarget? {
        let bearings = bearingSamples.filter(\.isFinite)
        guard let first = bearings.first else { return nil }
        // 5% inside the edge so float error never lands a candidate just outside.
        let distance = min(speed.metersPerSecond * 600, (range?.radiusMeters ?? .infinity) * 0.95)
        func candidate(from start: GeoCoordinate, bearing: Double) -> GeoCoordinate {
            JoystickGeodesy.destination(from: start, bearingDegrees: JoystickInput.normalizedBearing(bearing),
                                        distanceMeters: distance)
        }
        func target(_ coordinate: GeoCoordinate) -> WanderTarget? {
            guard JoystickGeodesy.distanceMeters(from: origin, to: coordinate) > 1 else { return nil }
            return WanderTarget(place: MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                                                coordinate: coordinate))
        }
        guard let range else { return target(candidate(from: origin, bearing: first)) }
        for bearing in bearings {
            let coordinate = candidate(from: origin, bearing: bearing)
            if range.contains(coordinate), let selected = target(coordinate) { return selected }
        }
        return target(candidate(from: range.anchor, bearing: first))
    }
}
