import Foundation
import Testing
@testable import GoFlyCore

struct JoystickModelTests {
    @Test func validWorldInputProducesBoundedStepsAtAllSupportedSpeedExtremes() throws {
        let full = try #require(JoystickInput(bearingDegrees: -450, strength: 2))
        #expect(full.bearingDegrees == 270 && full.strength == 1)
        let slow = try #require(full.displacement(speed: RouteSpeed(kilometersPerHour: 1)!))
        let normal = try #require(full.displacement(speed: .standard))
        let fastest = try #require(full.displacement(speed: RouteSpeed(kilometersPerHour: 120)!))
        #expect(abs(slow.distanceMeters - (1.0 / 3.6 * 0.5)) < 1e-15)
        #expect(abs(normal.distanceMeters - (20.0 / 3.6 * 0.5)) < 1e-15)
        #expect(abs(fastest.distanceMeters - (120.0 / 3.6 * 0.5)) < 1e-12, "no step cap")
        let pathStep = try #require(full.displacement(speed: .standard, seconds: MovementCadence.pathSeconds))
        #expect(abs(pathStep.distanceMeters - 20.0 / 3.6) < 1e-12)
        #expect(JoystickInput(bearingDegrees: 360, strength: -1)?.displacement(speed: .standard) == nil)
    }
    @Test func screenVectorsProduceEightWorldDirectionsAndRotateWithTheCamera() throws {
        let vectors: [(Double, Double)] = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
        for (index, vector) in vectors.enumerated() {
            let input = try #require(JoystickInput.fromScreenVector(x: vector.0, y: vector.1, radius: 1, cameraHeadingDegrees: 90))
            #expect(abs(input.bearingDegrees - Double((index * 45 + 90) % 360)) < 1e-12)
            #expect(input.strength == 1)
        }
        #expect(JoystickInput.fromScreenVector(x: 0, y: -0.5, radius: 1, cameraHeadingDegrees: -90)?.strength == 0.5)
        #expect(JoystickInput.fromScreenVector(x: 0, y: 0, radius: 1, cameraHeadingDegrees: 0)?.strength == 0)
        #expect(JoystickInput.fromScreenVector(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, radius: .leastNonzeroMagnitude, cameraHeadingDegrees: .greatestFiniteMagnitude)?.strength == 1)
    }

    @Test func invalidScalarsCannotReachARecipe() {
        for scalar in [Double.nan, .infinity, -.infinity] {
            #expect(JoystickInput(bearingDegrees: scalar, strength: 1) == nil)
            #expect(JoystickInput(bearingDegrees: 0, strength: scalar) == nil)
            #expect(JoystickDisplacement(bearingDegrees: scalar, distanceMeters: 1) == nil)
            #expect(JoystickDisplacement(bearingDegrees: 0, distanceMeters: scalar) == nil)
            #expect(JoystickInput.fromScreenVector(x: scalar, y: 1, radius: 1, cameraHeadingDegrees: 0) == nil)
            #expect(JoystickInput.fromScreenVector(x: 0, y: scalar, radius: 1, cameraHeadingDegrees: 0) == nil)
            #expect(JoystickInput.fromScreenVector(x: 0, y: 1, radius: scalar, cameraHeadingDegrees: 0) == nil)
            #expect(JoystickInput.fromScreenVector(x: 0, y: 1, radius: 1, cameraHeadingDegrees: scalar) == nil)
        }
        #expect(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 0) == nil)
        #expect(JoystickDisplacement(bearingDegrees: 0, distanceMeters: -1) == nil)
        #expect(JoystickInput.fromScreenVector(x: 0, y: 1, radius: 0, cameraHeadingDegrees: 0) == nil)
        #expect(JoystickInput.fromScreenVector(x: 0, y: 1, radius: -1, cameraHeadingDegrees: 0) == nil)
    }

    @Test func destinationsPreserveDistanceAcrossEightDirectionsTheDatelineAndExactPoles() throws {
        let equator = GeoCoordinate(latitude: 0, longitude: 0)!
        let north = JoystickGeodesy.destination(from: equator, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 10)!)
        #expect(abs(north.latitude - 0.00008993216059187306) < 1e-14)
        #expect(abs(north.longitude) < 1e-14)
        let origins = [equator, GeoCoordinate(latitude: 0, longitude: 179.99999)!, GeoCoordinate(latitude: 0, longitude: -179.99999)!, GeoCoordinate(latitude: 90, longitude: 42)!, GeoCoordinate(latitude: -90, longitude: -180)!]
        for origin in origins {
            for bearing in stride(from: 0.0, to: 360, by: 45) {
                let end = JoystickGeodesy.destination(from: origin, displacement: JoystickDisplacement(bearingDegrees: bearing, distanceMeters: 10)!)
                #expect((-180..<180).contains(end.longitude))
                let independentlyMeasured = try PlannedRoute(points: [origin, end], from: origin, to: end)
                #expect(abs(independentlyMeasured.totalDistanceMeters - 10) < 0.00001)
            }
        }
    }
    @Test func finiteBearingsAlwaysNormalizeIntoTheHalfOpenRangeDespiteRoundingAtNorth() throws {
        for bearing in [-Double.leastNonzeroMagnitude, -1e-20, -360.0, 360.0, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let input = try #require(JoystickInput(bearingDegrees: bearing, strength: 1))
            let displacement = try #require(JoystickDisplacement(bearingDegrees: bearing, distanceMeters: 1))
            #expect((0..<360).contains(input.bearingDegrees))
            #expect((0..<360).contains(displacement.bearingDegrees))
        }
    }
}
