import Foundation

public enum JoystickGeodesy {
    private static let radius = 6_371_000.0

    /// At a pole the origin's longitude defines the local north/east tangent basis.
    public static func destination(from origin: GeoCoordinate, displacement: JoystickDisplacement) -> GeoCoordinate {
        destination(from: origin, bearingDegrees: displacement.bearingDegrees, distanceMeters: displacement.distanceMeters)
    }

    static func destination(from origin: GeoCoordinate, bearingDegrees: Double, distanceMeters: Double) -> GeoCoordinate {
        let latitude = origin.latitude * .pi / 180, longitude = origin.longitude * .pi / 180
        let bearing = bearingDegrees * .pi / 180
        let angle = distanceMeters / radius
        let sinLat = sin(latitude), cosLat = cos(latitude), sinLon = sin(longitude), cosLon = cos(longitude)
        let radial = (x: cosLat * cosLon, y: cosLat * sinLon, z: sinLat)
        let north = (x: -sinLat * cosLon, y: -sinLat * sinLon, z: cosLat)
        let east = (x: -sinLon, y: cosLon, z: 0.0)
        let x = cos(angle) * radial.x + sin(angle) * (cos(bearing) * north.x + sin(bearing) * east.x)
        let y = cos(angle) * radial.y + sin(angle) * (cos(bearing) * north.y + sin(bearing) * east.y)
        let z = cos(angle) * radial.z + sin(angle) * (cos(bearing) * north.z + sin(bearing) * east.z)
        let resultLatitude = atan2(z, hypot(x, y)) * 180 / .pi
        let resultLongitude = atan2(y, x) * 180 / .pi
        return GeoCoordinate(latitude: resultLatitude, longitude: resultLongitude >= 180 ? resultLongitude - 360 : resultLongitude)!
    }

    public static func bearingDegrees(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180
        let delta = (b.longitude - a.longitude) * .pi / 180
        let y = sin(delta) * cos(latitudeB)
        let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func distanceMeters(from origin: GeoCoordinate, to target: GeoCoordinate) -> Double {
        if origin.latitude == target.latitude,
           abs(origin.latitude) == 90 || origin.longitude == target.longitude || abs(origin.longitude - target.longitude) == 360 { return 0 }
        let a = radial(origin), b = radial(target)
        let cross = (x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
        return radius * atan2(hypot(hypot(cross.x, cross.y), cross.z), a.x * b.x + a.y * b.y + a.z * b.z)
    }

    public static func resolveTarget(from origin: GeoCoordinate, step: JoystickTargetStep) -> JoystickTargetStepResolution {
        let distance = distanceMeters(from: origin, to: step.coordinate)
        guard distance > 0 else {
            return JoystickTargetStepResolution(coordinate: step.coordinate, bearingDegrees: nil, arrived: true)
        }
        let latitude = origin.latitude * .pi / 180, longitude = origin.longitude * .pi / 180
        let target = radial(step.coordinate)
        let north = -sin(latitude) * cos(longitude) * target.x - sin(latitude) * sin(longitude) * target.y + cos(latitude) * target.z
        let east = -sin(longitude) * target.x + cos(longitude) * target.y
        let bearing = hypot(north, east) < 1e-15 ? 0 : JoystickInput.normalizedBearing(atan2(east, north) * 180 / .pi)
        if distance <= step.maximumDistanceMeters {
            return JoystickTargetStepResolution(coordinate: step.coordinate, bearingDegrees: bearing, arrived: true)
        }
        return JoystickTargetStepResolution(coordinate: destination(from: origin, bearingDegrees: bearing,
            distanceMeters: step.maximumDistanceMeters), bearingDegrees: bearing, arrived: false)
    }

    private static func radial(_ coordinate: GeoCoordinate) -> (x: Double, y: Double, z: Double) {
        let latitude = coordinate.latitude * .pi / 180, longitude = coordinate.longitude * .pi / 180
        return (cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
    }
}
