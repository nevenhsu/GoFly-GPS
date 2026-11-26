import Foundation
import Testing
@testable import GoFlyCore

struct RouteModelsTests {
    @Test func joiningLegsPreservesRoadVerticesAndRejectsDisconnectedBoundaries() throws {
        let points = (0...4).map { GeoCoordinate(latitude: 25 + Double($0) * 0.0001, longitude: 121)! }
        let first = try PlannedRoute(points: Array(points[0...2]), from: points[0], to: points[2])
        let second = try PlannedRoute(points: Array(points[2...4]), from: points[2], to: points[4])
        #expect(try PlannedRoute(legs: [first, second]).points == points)
        #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(legs: [second, first]) }
        #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(legs: []) }
    }

    @Test func selectedPlacesNeverAnchorOrLimitTheReturnedRoadGeometry() throws {
        let station = GeoCoordinate(latitude: 25.0477816, longitude: 121.5171495)!
        let tower = GeoCoordinate(latitude: 25.033649, longitude: 121.564824)!
        let road = [GeoCoordinate(latitude: 25.0471644, longitude: 121.5170253)!,
                    GeoCoordinate(latitude: 25.04, longitude: 121.54)!,
                    GeoCoordinate(latitude: 25.0336355, longitude: 121.5652920)!]
        let route = try PlannedRoute(points: [road[0]] + road, from: station, to: tower)
        #expect(route.points == road)
        #expect(route.start == road.first)
        #expect(route.end == road.last)
        // There is no replacement distance cap, even for far-away selected POIs.
        let remote = GeoCoordinate(latitude: 0, longitude: 0)!
        #expect(try PlannedRoute(points: road, from: remote, to: remote).points == road)
    }

    @Test func pointCapAppliesOnlyToReturnedGeometry() throws {
        let road = (0..<10_000).map { GeoCoordinate(latitude: 0, longitude: Double($0) * 0.0000001)! }
        #expect(try PlannedRoute(points: road).points.count == 10_000)
        #expect(throws: RouteExecutionFailure.invalidPath) {
            try PlannedRoute(points: road + [GeoCoordinate(latitude: 0, longitude: 1)!])
        }
    }

    @Test func routeSpeedAndDraftKeepValidatedValuesAndStableNodeIdentity() throws {
        let draft = RouteDraft()
        #expect(draft.nodes.count == 2)
        #expect(draft.start?.value == .current)
        #expect(draft.destination?.value == .empty)
        #expect(draft.speed.kilometersPerHour == 20)
        #expect(RouteSpeed(kilometersPerHour: 0) == nil)
        #expect(RouteSpeed(kilometersPerHour: 1) != nil)
        #expect(RouteSpeed(kilometersPerHour: 120) != nil)
        #expect(RouteSpeed(kilometersPerHour: 121) == nil)
        #expect(RouteSpeed(kilometersPerHour: 36)?.metersPerSecond == 10)
    }

    @Test func plannedGeometryDeduplicatesAndInterpolatesSphericalDistance() throws {
        let start = GeoCoordinate(latitude: 0, longitude: 0)!
        let end = GeoCoordinate(latitude: 0, longitude: 1)!
        let route = try PlannedRoute(points: [start, start, end], from: start, to: end)
        #expect(route.points == [start, end])
        #expect(abs(route.totalDistanceMeters - 111_194.92664455874) < 0.001)
        #expect(route.coordinate(at: 0) == start)
        #expect(route.coordinate(at: route.totalDistanceMeters) == end)
        #expect(abs(try #require(route.coordinate(at: route.totalDistanceMeters / 2)).longitude - 0.5) < 0.000001)
        #expect(route.coordinate(at: .nan) == nil)
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start], from: start, to: end) }
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start, start], from: start, to: end) }
    }
    @Test func geographicAliasesAreZeroLengthAndAntimeridianInterpolationUsesTheShortArc() throws {
        for (start, end) in [(GeoCoordinate(latitude: 90, longitude: 0)!, GeoCoordinate(latitude: 90, longitude: 90)!),
                             (GeoCoordinate(latitude: 0, longitude: 180)!, GeoCoordinate(latitude: 0, longitude: -180)!)] {
            #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start, end], from: start, to: end) }
        }
        let start = GeoCoordinate(latitude: 0, longitude: 179.9)!, end = GeoCoordinate(latitude: 0, longitude: -179.9)!
        let route = try PlannedRoute(points: [start, end], from: start, to: end)
        #expect(abs(route.totalDistanceMeters - 22_238.98532891) < 0.001)
        #expect(abs(abs(try #require(route.coordinate(at: route.totalDistanceMeters / 2)).longitude) - 180) < 0.000001)
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: Array(repeating: start, count: 10_001), from: start, to: end) }
    }
}
