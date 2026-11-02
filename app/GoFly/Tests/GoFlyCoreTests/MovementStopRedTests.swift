import Foundation
import Testing
@testable import GoFlyCore

enum RedTests {
    /// Intentional reproduction of the historical movement-stop defect H1.
    /// It fails on purpose until
    /// stage C fixes it, so it is skipped by default and enabled with
    /// `GOFLY_RED_TESTS=1`.
    static var enabled: Bool { ProcessInfo.processInfo.environment["GOFLY_RED_TESTS"] == "1" }
}

/// Stage A reproductions. Run with:
/// `GOFLY_RED_TESTS=1 swift test --filter MovementStopRedTests`
struct MovementStopRedTests {
    /// H1 (foreground): every 500 ms tick re-runs identity and DDI/support
    /// verification. `NativeDeviceService.movePoint` calls `prepare()` before each
    /// `setLocation`, so one failed roundtrip out of four ends the movement.
    @Test(.enabled(if: RedTests.enabled))
    func preparedSessionDoesNotRepeatIdentityAndSupportWorkEveryTick() throws {
        let session = CountingSession()
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound")
        try verified.prepare()
        let afterFirstPrepare = session.counts
        let coordinate = try #require(GeoCoordinate(latitude: 25.033, longitude: 121.565))

        for _ in 0..<3 {
            // The exact call order of NativeDeviceService.movePoint.
            try verified.prepare()
            _ = verified.movePoint(to: coordinate, dispatch: PointDispatchGate())
        }
        let afterTicks = session.counts
        #expect(afterTicks.identity - afterFirstPrepare.identity == 0,
                "each tick re-read UniqueDeviceID over a fresh lockdown connection")
        #expect(afterTicks.support - afterFirstPrepare.support == 0,
                "each tick re-queries the cryptex/DDI support state")
    }
}

private final class CountingSession: DeviceSession {
    struct Counts {
        var identity = 0
        var support = 0
        var set = 0
    }

    private(set) var counts = Counts()

    func deviceIdentifier() throws -> String {
        counts.identity += 1
        return "bound"
    }

    func isSupportPrepared() throws -> Bool {
        counts.support += 1
        return true
    }

    func mountProvisionedSupport() throws {}

    func validateLocationService() throws {}

    func clearLocation() throws {}

    func setLocation(_ coordinate: GeoCoordinate) throws { counts.set += 1 }
}
