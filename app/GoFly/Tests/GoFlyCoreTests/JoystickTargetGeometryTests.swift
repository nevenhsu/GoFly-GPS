import Foundation
import Testing
@testable import GoFlyCore

struct JoystickTargetGeometryTests {
    @Test func aRoadStepThatRoundsAHairPastTheCapStillArrives() throws {
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        let target = GeoCoordinate(latitude: 25.00006, longitude: 121.00003)!
        let exact = JoystickGeodesy.distanceMeters(from: origin, to: target)
        let result = JoystickGeodesy.resolveTarget(from: origin, step: JoystickTargetStep(
            targetID: UUID(), coordinate: target, maximumDistanceMeters: exact - 1e-9)!)
        #expect(result.arrived && result.coordinate == target)
        let short = JoystickGeodesy.resolveTarget(from: origin, step: JoystickTargetStep(
            targetID: UUID(), coordinate: target, maximumDistanceMeters: exact - 0.5)!)
        #expect(!short.arrived)
    }
    @Test func zeroDistanceResolvesTheExactTargetWithoutInventingABearing() throws {
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        let target = JoystickTargetStep(targetID: UUID(), coordinate: origin, maximumDistanceMeters: 10)!
        let result = JoystickGeodesy.resolveTarget(from: origin, step: target)
        #expect(result.coordinate == origin && result.bearingDegrees == nil && result.arrived)
        let pole = GeoCoordinate(latitude: 90, longitude: 42)!
        let poleAlias = GeoCoordinate(latitude: 90, longitude: -90)!
        let aliased = JoystickGeodesy.resolveTarget(from: pole,
            step: JoystickTargetStep(targetID: UUID(), coordinate: poleAlias, maximumDistanceMeters: 10)!)
        #expect(aliased.coordinate == poleAlias && aliased.bearingDegrees == nil && aliased.arrived)
    }
    @Test func aFinalStepClampsToTheExactTargetAndLongerStepsAdvanceOnlyTheAllowedDistance() throws {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)!
        let close = GeoCoordinate(latitude: 0.00001, longitude: 0)!
        let final = JoystickGeodesy.resolveTarget(from: origin,
            step: JoystickTargetStep(targetID: UUID(), coordinate: close, maximumDistanceMeters: 10)!)
        #expect(final.coordinate == close && final.arrived)
        #expect(final.bearingDegrees == 0)
        let far = GeoCoordinate(latitude: 0, longitude: 1)!
        let progress = JoystickGeodesy.resolveTarget(from: origin,
            step: JoystickTargetStep(targetID: UUID(), coordinate: far, maximumDistanceMeters: 10)!)
        #expect(!progress.arrived && progress.bearingDegrees == 90)
        #expect(abs(progress.coordinate.longitude - 0.00008993216059187306) < 1e-14)
        #expect(abs(progress.coordinate.latitude) < 1e-14)
        let measured = try PlannedRoute(points: [origin, progress.coordinate], from: origin, to: progress.coordinate)
        #expect(abs(measured.totalDistanceMeters - 10) < 1e-8)
    }
    @Test func shortestTargetStepsCrossTheDatelineAndRemainStableAtPolesAndAntipodes() throws {
        let dateline = GeoCoordinate(latitude: 0, longitude: 179.99999)!
        let crossing = JoystickGeodesy.resolveTarget(from: dateline,
            step: JoystickTargetStep(targetID: UUID(), coordinate: GeoCoordinate(latitude: 0, longitude: -179.999)!, maximumDistanceMeters: 10)!)
        #expect(crossing.coordinate.longitude < 0 && !crossing.arrived)
        #expect(abs((crossing.bearingDegrees ?? 0) - 90) < 1e-8)
        #expect(abs(JoystickGeodesy.distanceMeters(from: dateline, to: crossing.coordinate) - 10) < 1e-6)
        for latitude in [90.0, -90.0] {
            let pole = GeoCoordinate(latitude: latitude, longitude: 42)!
            let target = GeoCoordinate(latitude: latitude > 0 ? 89 : -89, longitude: 42)!
            let result = JoystickGeodesy.resolveTarget(from: pole,
                step: JoystickTargetStep(targetID: UUID(), coordinate: target, maximumDistanceMeters: 10)!)
            #expect(abs(result.coordinate.longitude - 42) < 1e-7)
            #expect(abs(JoystickGeodesy.distanceMeters(from: pole, to: result.coordinate) - 10) < 1e-6)
        }
        let origin = GeoCoordinate(latitude: 0, longitude: 0)!, opposite = GeoCoordinate(latitude: 0, longitude: 180)!
        let antipodal = JoystickGeodesy.resolveTarget(from: origin,
            step: JoystickTargetStep(targetID: UUID(), coordinate: opposite, maximumDistanceMeters: 10)!)
        #expect(antipodal.bearingDegrees == 0 && !antipodal.arrived)
        #expect(abs(antipodal.coordinate.latitude - 0.00008993216059187306) < 1e-14)
        #expect(abs(JoystickGeodesy.distanceMeters(from: origin, to: opposite) - 20015086.79602057) < 1e-6)
        let alias = GeoCoordinate(latitude: 0, longitude: -180)!
        let coincident = JoystickGeodesy.resolveTarget(from: opposite,
            step: JoystickTargetStep(targetID: UUID(), coordinate: alias, maximumDistanceMeters: 10)!)
        #expect(coincident.coordinate == alias && coincident.arrived && coincident.bearingDegrees == nil)
    }
}
