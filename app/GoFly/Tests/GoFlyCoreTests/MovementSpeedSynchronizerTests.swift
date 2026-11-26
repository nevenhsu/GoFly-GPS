import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct MovementSpeedSynchronizerTests {
    @Test func presetsAndDefaultMatchTheSharedSpeedSpec() {
        #expect(RouteSpeed.presets.map(\.kilometersPerHour) == [5, 20, 50, 100])
        #expect(RouteSpeed.standard.kilometersPerHour == 20)
        #expect(RouteSpeed(kilometersPerHour: 0) == nil)
        #expect(RouteSpeed(kilometersPerHour: 121) == nil)
    }

    @Test func initialPreferenceAppliesToBothControllers() {
        let fixture = Fixture(initial: RouteSpeed(kilometersPerHour: 50)!)
        #expect(fixture.route.draft.speed.kilometersPerHour == 50)
        #expect(fixture.joystick.speed.kilometersPerHour == 50)
    }

    @Test func routeChangeIsSavedAndMirroredToTheJoystick() async {
        let fixture = Fixture(initial: .standard)
        #expect(fixture.route.setSpeed(RouteSpeed(kilometersPerHour: 100)!))
        await settle { fixture.joystick.speed.kilometersPerHour == 100 }
        #expect(fixture.saved == [100])
    }

    @Test func joystickChangeIsSavedAndMirroredToTheRoute() async {
        let fixture = Fixture(initial: .standard)
        #expect(fixture.joystick.setSpeed(RouteSpeed(kilometersPerHour: 5)!))
        await settle { fixture.route.draft.speed.kilometersPerHour == 5 }
        #expect(fixture.saved == [5])
    }

    @Test func alternatingChangesSettleWithoutBouncingBack() async throws {
        let fixture = Fixture(initial: .standard)
        #expect(fixture.route.setSpeed(RouteSpeed(kilometersPerHour: 100)!))
        #expect(fixture.joystick.setSpeed(RouteSpeed(kilometersPerHour: 5)!))
        try await Task.sleep(for: .milliseconds(200))
        #expect(fixture.route.draft.speed.kilometersPerHour == 5)
        #expect(fixture.joystick.speed.kilometersPerHour == 5)
        #expect(fixture.saved == [100, 5], "each user change is saved once, nothing oscillates")
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private final class Box { var values: [Int] = [] }

    @MainActor private struct Fixture {
        let route: RouteExecutionController
        let joystick: JoystickMovementController
        let synchronizer: MovementSpeedSynchronizer
        private let box = Box()
        var saved: [Int] { box.values }

        init(initial: RouteSpeed) {
            let service = ServiceController(service: SpeedDevice())
            route = RouteExecutionController(planner: SpeedPlanner(), commands: service, search: SpeedSearch())
            joystick = JoystickMovementController(commands: service)
            let box = self.box
            synchronizer = MovementSpeedSynchronizer(route: route, joystick: joystick, initial: initial,
                                                     onChange: { box.values.append($0.kilometersPerHour) })
        }
    }
}

private struct SpeedPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}
private struct SpeedSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor SpeedDevice: DeviceService {
    func prepare() async throws {}
    func resetClientConnection() async throws {}
    func rebuildClientConnection() async throws {}
    func clearLocation() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}
