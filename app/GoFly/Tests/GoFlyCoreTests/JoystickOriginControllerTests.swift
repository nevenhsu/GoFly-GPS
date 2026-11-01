import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct JoystickOriginControllerTests {
    @Test func freshGPSAlreadyGivesTheJoystickAnOrigin() async {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        service.observeRealLocation(location())
        let (origin, host) = controller(service)

        origin.ensure()
        #expect(host.fixRequests == 0 && origin.request == JoystickOriginRequest())
        #expect(service.pointState == .idle)
    }

    @Test func theOriginTeleportIsNeverReplacedAndSettlesOnlyForItsIntent() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        let (origin, _) = controller(service)

        origin.ensure()
        origin.fixAccepted(gps)
        let intentID = try #require(origin.request.intentID)
        #expect(origin.isOrigin(intentID))
        origin.ensure()
        origin.fixAccepted(GeoCoordinate(latitude: 26, longitude: 121)!)
        #expect(origin.request.intentID == intentID, "An origin in flight is never replaced")

        #expect(!origin.settle(UUID()))
        #expect(origin.settle(intentID))
        #expect(origin.request == JoystickOriginRequest() && !origin.isOrigin(intentID))
        await wait { await device.waiting }
        #expect(await device.coordinates == [gps])
        await device.finish(.acknowledged)
    }

    @Test func withoutAPositionItAsksForAFixAndSendsTheAcceptedOne() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        let (origin, host) = controller(service)

        origin.ensure()
        #expect(host.fixRequests == 1)
        #expect(origin.request == JoystickOriginRequest(isSetting: true))

        origin.fixAccepted(gps)
        #expect(origin.request.isSetting && origin.request.intentID != nil)
        await wait { await device.waiting }
        #expect(await device.coordinates == [gps])
        await device.finish(.acknowledged)
    }

    @Test func touchingWithoutAnOriginTeleportsToTheMapCentre() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        let (origin, host) = controller(service)
        let center = try #require(GeoCoordinate(latitude: 25.03, longitude: 121.56))
        host.mapCenter = center

        origin.establishFromMap()
        #expect(origin.request.isSetting && origin.request.intentID != nil)
        await wait { await device.waiting }
        #expect(await device.coordinates == [center])
        await device.finish(.acknowledged)
    }

    @Test func aMissingFixEndsTheRequest() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let (origin, _) = controller(service)

        origin.ensure()
        origin.fixUnavailable()
        #expect(origin.request == JoystickOriginRequest())
    }

    @Test func anInvalidAcceptedFixEndsAWaitingRequestWithoutTeleporting() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let (origin, _) = controller(service)

        origin.ensure()
        origin.fixAccepted(nil)
        #expect(origin.request == JoystickOriginRequest())
        #expect(service.pointState == .idle)
    }

    @Test func outsideJoystickModeNothingIsRequestedOrFlagged() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let (origin, host) = controller(service)
        host.joystickMode = false

        origin.ensure()
        origin.fixUnavailable()
        origin.receive(.availabilityChanged)
        #expect(host.fixRequests == 0 && origin.request == JoystickOriginRequest())
        #expect(origin.request == JoystickOriginRequest())
    }

    @Test func availabilityRetriesOnlyInAnActiveSceneWithNoRequest() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let (origin, host) = controller(service)

        host.sceneActive = false
        origin.receive(.availabilityChanged)
        #expect(host.fixRequests == 0)

        host.sceneActive = true
        origin.receive(.ended(UUID()))
        #expect(host.fixRequests == 0)
        origin.receive(.availabilityChanged)
        #expect(host.fixRequests == 1)
        origin.receive(.availabilityChanged)
        #expect(host.fixRequests == 1, "A request already waiting for a fix is not restarted")
    }

    @Test func goInJoystickModeReplacesAnOriginWaitingForAFix() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        let (origin, _) = controller(service)

        origin.ensure()
        origin.go(to: TeleportCandidate(place: place(gps)))
        let intentID = try #require(origin.request.intentID)
        #expect(!origin.request.isSetting)
        #expect(preparingIntentID(service) == intentID)
        await wait { await device.waiting }
        await device.finish(.acknowledged)
    }

    @Test func goOutsideJoystickModeBecomesTheOriginOnlyWhileOneIsRequested() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device); service.setMovementConnectionAvailable(true)
        let (origin, host) = controller(service)

        origin.ensure()
        host.joystickMode = false
        origin.go(to: TeleportCandidate(place: place(gps)))
        #expect(origin.request.isSetting && origin.request.intentID == preparingIntentID(service))
        await wait { await device.waiting }
        await device.finish(.acknowledged)
    }

    @Test func cancelDropsTheRequest() {
        let service = ServiceController(service: JoystickControlledDevice()); service.setMovementConnectionAvailable(true)
        let (origin, _) = controller(service)
        origin.ensure()
        origin.cancel()
        #expect(origin.request == JoystickOriginRequest())
    }

    private let gps = GeoCoordinate(latitude: 25, longitude: 121)!

    private func controller(_ service: ServiceController) -> (JoystickOriginController, RecordingOriginHost) {
        let origin = JoystickOriginController(service: service, joystick: JoystickMovementController(commands: service))
        let host = RecordingOriginHost()
        origin.attach(host.host)
        return (origin, host)
    }
    private func preparingIntentID(_ service: ServiceController) -> UUID? {
        if case .preparing(let intent) = service.pointState { return intent.id }
        return nil
    }
    private func location() -> RealLocationObservation { RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date())! }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

@MainActor
private final class RecordingOriginHost {
    var joystickMode = true
    var sceneActive = true
    var fixRequests = 0
    var mapCenter: GeoCoordinate?
    var host: JoystickOriginHost {
        JoystickOriginHost(
            isJoystickMode: { self.joystickMode },
            isSceneActive: { self.sceneActive },
            requestLocationFix: { self.fixRequests += 1 },
            mapCenter: { self.mapCenter })
    }
}
