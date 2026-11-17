import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct FlyOriginTests {
    private let home = GeoCoordinate(latitude: 25.0330, longitude: 121.5654)!
    private let target = GeoCoordinate(latitude: 35.6812, longitude: 139.7671)!

    @Test func freshFixBecomesOriginAndStopReturnsThereBeforeClearing() async throws {
        let device = LoggingDevice()
        let controller = makeController(device)
        controller.observeRealLocation(fix(at: home, age: 2))
        try await fly(controller)
        #expect(controller.flyOrigin == home)

        #expect(controller.stop())
        await wait { controller.clearState == .confirmed }
        #expect(await device.log == ["prepare", "move \(target)", "move \(home)", "clear"])
        #expect(controller.flyOrigin == nil)
        #expect(controller.flyOriginReturn?.coordinate == home)
        #expect(controller.positionMarker?.coordinate == home)
        #expect(controller.positionMarker?.source == .gps)
    }

    @Test func cachedSystemFixIsTheOriginWhenNoFreshFixExists() async throws {
        let device = LoggingDevice()
        let controller = makeController(device)
        let cached = fix(at: home, age: 300)
        controller.cachedRealLocation = { cached }
        try await fly(controller)
        #expect(controller.flyOrigin == home)
    }

    @Test(arguments: [true, false])
    func withoutAnUsableFixStopOnlyClears(staleCache: Bool) async throws {
        let device = LoggingDevice()
        let controller = makeController(device)
        let stale = fix(at: home, age: ServiceController.flyOriginCachedFixMaxAge + 60)
        controller.cachedRealLocation = { staleCache ? stale : nil }
        try await fly(controller)
        #expect(controller.flyOrigin == nil)

        #expect(controller.stop())
        await wait { controller.clearState == .confirmed }
        #expect(await device.log == ["prepare", "move \(target)", "clear"])
    }

    @Test func laterWritesKeepTheFirstOrigin() async throws {
        let device = LoggingDevice()
        let controller = makeController(device)
        controller.observeRealLocation(fix(at: home, age: 1))
        try await fly(controller)
        let elsewhere = try #require(GeoCoordinate(latitude: 1, longitude: 1))
        controller.cachedRealLocation = { fix(at: elsewhere, age: 1) }
        try await fly(controller)
        #expect(controller.flyOrigin == home)
    }

    @Test func restoredOriginIsReturnedToBeforeAColdClear() async throws {
        let device = LoggingDevice()
        let controller = makeController(device)
        controller.restoreFlyOrigin(home)
        controller.markColdClearPending()
        #expect(controller.beginColdClear())
        await wait { controller.clearState == .confirmed }
        #expect(await device.log == ["move \(home)", "clear"])
        #expect(controller.flyOrigin == nil)
    }

    @Test func failedReturnStillClears() async throws {
        let device = LoggingDevice(moveOutcome: .notSent(.serviceUnavailable))
        let controller = makeController(device)
        controller.restoreFlyOrigin(home)
        #expect(controller.restoreGPS())
        await wait { controller.clearState == .confirmed }
        #expect(await device.log == ["move \(home)", "clear"])
    }

    private func makeController(_ device: LoggingDevice) -> ServiceController {
        let controller = ServiceController(service: device)
        controller.flyOriginReturnHold = .zero
        return controller
    }

    private func fly(_ controller: ServiceController) async throws {
        let place = MapPlace(id: .coordinate(target), title: "Target", coordinate: target)
        try #require(controller.teleport(to: TeleportCandidate(place: place)))
        await wait { !controller.nativeBusy }
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<2_000 where !(await condition()) { await Task.yield() }
    }
}

private func fix(at coordinate: GeoCoordinate, age: TimeInterval) -> RealLocationObservation {
    RealLocationObservation(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            horizontalAccuracy: 10, observedAt: Date().addingTimeInterval(-age))!
}

private actor LoggingDevice: DeviceService {
    var log: [String] = []
    let moveOutcome: PointDeliveryOutcome
    init(moveOutcome: PointDeliveryOutcome = .acknowledged) { self.moveOutcome = moveOutcome }
    func prepare() async throws { log.append("prepare") }
    func clearLocation() async throws { log.append("clear") }
    func resetClientConnection() async throws { log.append("reset") }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        log.append("move \(coordinate)")
        return moveOutcome
    }
}
