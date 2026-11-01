import Testing
@testable import GoFlyCore

@MainActor
struct WanderRangeTests {
    private let anchor = GeoCoordinate(latitude: 25, longitude: 121)!

    @Test func radiusClampsToSupportedRangeAndDefaultsTo5() {
        #expect(WanderRadius.default.kilometers == 5)
        #expect(WanderRadius(kilometers: 0.01).kilometers == 0.1)
        #expect(WanderRadius(kilometers: 250).kilometers == 100)
        #expect(WanderRadius(kilometers: .nan).kilometers == 5)
        #expect(WanderRadius(kilometers: 2.26).kilometers == 2.3)
    }

    @Test func selectionStaysInsideSmallRadius() throws {
        let range = WanderRange(anchor: anchor, radiusMeters: 100)
        for bearing in stride(from: 0.0, to: 360, by: 15) {
            let target = try #require(WanderTargetSelector.select(
                origin: anchor, speed: .standard, bearingSamples: [bearing], range: range))
            #expect(range.contains(target.coordinate))
        }
    }

    @Test func largeRadiusKeepsTheTenMinuteRing() throws {
        let range = WanderRange(anchor: anchor, radiusMeters: 100_000)
        let target = try #require(WanderTargetSelector.select(
            origin: anchor, speed: .standard, bearingSamples: [90], range: range))
        let distance = JoystickGeodesy.distanceMeters(from: anchor, to: target.coordinate)
        #expect(abs(distance - RouteSpeed.standard.metersPerSecond * 600) < 1)
    }

    @Test func originOutsideTheRangeHeadsBackInside() throws {
        let range = WanderRange(anchor: anchor, radiusMeters: 1_000)
        let outside = JoystickGeodesy.destination(from: anchor, displacement: JoystickDisplacement(bearingDegrees: 90, distanceMeters: 20_000)!)
        let target = try #require(WanderTargetSelector.select(
            origin: outside, speed: .standard, bearingSamples: [90, 45, 10], range: range))
        #expect(range.contains(target.coordinate))
    }

    @Test func anchorOnlyMovesWhenTeleportingWithoutWander() {
        let other = GeoCoordinate(latitude: 24, longitude: 120)!
        let controller = WanderRangeController(anchor: anchor)
        controller.teleportAcknowledged(at: other, wanderRunning: true)
        #expect(controller.anchor == anchor)
        controller.teleportAcknowledged(at: other, wanderRunning: false)
        #expect(controller.anchor == other)
    }

    @Test func firstWanderOriginBecomesTheAnchorAndRadiusChangeKeepsIt() {
        let controller = WanderRangeController()
        #expect(controller.range(origin: anchor).anchor == anchor)
        controller.setRadius(WanderRadius(kilometers: 0.1))
        let moved = GeoCoordinate(latitude: 26, longitude: 121)!
        #expect(controller.range(origin: moved).anchor == anchor)
        #expect(controller.range(origin: moved).radiusMeters == 100)
        controller.setVisible(false)
        #expect(controller.range(origin: moved).radiusMeters == 100)
    }

    @Test func joystickSelectionUsesTheConfiguredRange() throws {
        let controller = JoystickMovementController(
            commands: ServiceController(service: JoystickControlledDevice()), wanderBearingSamples: { [90, 270, 0, 180] })
        let range = WanderRange(anchor: anchor, radiusMeters: 150)
        controller.wanderRange = { _ in range }
        let target = try #require(controller.selectWanderTarget(from: anchor))
        #expect(range.contains(target.coordinate))
    }

    @Test func theAnchorStaysAtTheFirstKnownPositionWhilePositionsMove() {
        let controller = WanderRangeController()
        controller.adoptAnchorIfNeeded(anchor)
        controller.adoptAnchorIfNeeded(GeoCoordinate(latitude: 26, longitude: 122)!)
        #expect(controller.anchor == anchor)
    }

    @Test func aNewWanderOutsideTheRangeRecentresItAndOneInsideKeepsIt() {
        let controller = WanderRangeController(radius: WanderRadius(kilometers: 1), anchor: anchor)
        let inside = JoystickGeodesy.destination(from: anchor, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 500)!)
        controller.wanderStarting(at: inside)
        #expect(controller.anchor == anchor)
        let far = GeoCoordinate(latitude: 24, longitude: 120)!
        controller.wanderStarting(at: far)
        #expect(controller.anchor == far)
    }
}
