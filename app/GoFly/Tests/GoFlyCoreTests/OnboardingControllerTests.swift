import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct OnboardingControllerTests {
    @Test func backNavigationIgnoresPermissionAndVPNCallbacksFromDepartedPages() async {
        let permission = ControlledPermission()
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: permission)
        controller.advanceWelcome()
        let request = Task { await controller.allowLocation() }
        await wait { permission.isWaiting }
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        controller.goBack()
        #expect(controller.step == .location)
        permission.finish(.authorized)
        await request.value
        await probe.finish()
        await wait { !controller.isChecking }
        #expect(controller.step == .location)
        #expect(controller.vpnState == .unknown)
        #expect(!controller.canAdvanceVPN)
        controller.goBack()
        #expect(controller.step == .welcome)
        #expect(!controller.isRequestingLocation)
    }

    @Test func visibleVPNPageNeverChecksUntilUserAsksAndFailureDoesNotRetryAutomatically() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(await probe.requests == 0)
        #expect(controller.vpnState == .unknown)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        await probe.finish(.failure(TunnelProbeFailure.unavailable))
        await wait { controller.vpnState == .unavailable }
        for _ in 0..<20 { await Task.yield() }
        #expect(await probe.requests == 1)
        #expect(controller.vpnState == .unavailable)
        controller.setVPNActive(false)
    }

    @Test func checkInterruptedByPermissionAlertResumesWhenForegroundReturns() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        controller.setVPNActive(false) // system alert takes the foreground
        await probe.finish(.failure(CancellationError()))
        await wait { !controller.isChecking }
        controller.setVPNActive(true)
        await wait { await probe.requests == 2 }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        controller.setVPNActive(false)
        controller.setVPNActive(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(await probe.requests == 2) // nothing was in flight, so no automatic check
    }

    @Test func backgroundInvalidatesQueuedNextAndReturnWaitsForOldProbeBeforeRechecking() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        var advances = 0
        controller.advanceVPN { advances += 1 }
        controller.setVPNActive(false)
        #expect(!controller.canAdvanceVPN)
        #expect(!controller.isAdvancing)
        #expect(controller.vpnState == .unknown)
        controller.setVPNActive(true)
        #expect(await probe.requests == 2)
        await probe.finish() // Deliberately returns late success after cancellation.
        // The interrupted user check resumes once the old probe has ended.
        await wait { await probe.requests == 3 }
        #expect(advances == 0)
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        #expect(controller.step == .vpn)
        #expect(advances == 0)
        controller.advanceVPN { advances += 1 }
        await wait { await probe.requests == 4 }
        await probe.finish(.failure(TunnelProbeFailure.timedOut))
        await wait { controller.vpnState == .timedOut }
        #expect(!controller.canAdvanceVPN)
        #expect(advances == 0)
        #expect(await probe.maximumConcurrent == 1)
        controller.setVPNActive(false)
    }

    @Test func nextRequiresNewProbeAfterTapAndNeverOverlapsExistingCheck() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        var advances = 0
        controller.advanceVPN { advances += 1 }
        #expect(controller.isAdvancing)
        #expect(!controller.canAdvanceVPN)
        controller.advanceVPN { advances += 1 }
        controller.checkConnection()
        #expect(await probe.requests == 2)
        await probe.finish()
        await wait { await probe.requests == 3 }
        #expect(advances == 0)
        await probe.finish()
        await wait { advances == 1 }
        #expect(controller.step == .complete)
        #expect(await probe.maximumConcurrent == 1)
    }

    @Test func visibleVPNChecksActualReachabilityWithoutAutoAdvancing() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { await probe.requests == 1 }
        #expect(!controller.canAdvanceVPN)
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        #expect(controller.step == .vpn)
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        await probe.finish(.failure(TunnelProbeFailure.unavailable))
        await wait { controller.vpnState == .unavailable }
        #expect(!controller.canAdvanceVPN)
        #expect(controller.step == .vpn)
        controller.setVPNActive(false)
    }

    @Test(arguments: [LocationAuthorization.authorized, .denied])
    func permissionDecisionContinuesWithoutWaitingForGPS(decision: LocationAuthorization) async {
        let permission = PermissionStub(decision)
        let controller = OnboardingController(probe: ProbeStub(), location: permission)
        controller.advanceWelcome()
        await controller.allowLocation()
        #expect(controller.step == .vpn)
        #expect(controller.locationAuthorization == decision)
        #expect(permission.requests == 1)
        #expect(!controller.isRequestingLocation)
    }

    @Test func skippedLocationReachesVPNWithoutRequestingPermissionOrStartingService() async {
        let permission = PermissionStub(.notDetermined)
        let probe = ProbeStub()
        let controller = OnboardingController(probe: probe, location: permission)
        #expect(controller.step == .welcome)
        controller.advanceWelcome()
        #expect(controller.step == .location)
        controller.skipLocation()
        #expect(controller.step == .vpn)
        #expect(permission.requests == 0)
        #expect(await probe.requests == 0)
        #expect(!controller.canAdvanceVPN)
    }

    @Test func failedCheckPublishesProbeDetailAndInactivePageClearsIt() async {
        let controller = OnboardingController(probe: DetailProbe(), location: PermissionStub(.authorized))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        controller.checkConnection()
        await wait { controller.vpnState == .timedOut }
        #expect(controller.vpnFailureDetail == DetailProbe.detail)
        controller.setVPNActive(false)
        #expect(controller.vpnFailureDetail == nil)
    }

    @Test func locationPageRefreshesAuthorizationChangedInSettings() {
        let permission = PermissionStub(.denied)
        let controller = OnboardingController(probe: ProbeStub(), location: permission)
        controller.refreshLocationAuthorization()
        #expect(controller.locationAuthorization == .denied)
        controller.advanceWelcome()
        permission.authorization = .authorized
        controller.refreshLocationAuthorization()
        #expect(controller.locationAuthorization == .authorized)
        #expect(permission.requests == 0)
        #expect(controller.step == .location)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

@MainActor
private final class PermissionStub: LocationAuthorizing {
    var authorization: LocationAuthorization
    var requests = 0
    init(_ authorization: LocationAuthorization) { self.authorization = authorization }
    func requestAuthorization() async -> LocationAuthorization {
        requests += 1
        return authorization
    }
}

@MainActor
private final class ControlledPermission: LocationAuthorizing {
    var authorization: LocationAuthorization = .notDetermined
    private var continuation: CheckedContinuation<LocationAuthorization, Never>?
    var isWaiting: Bool { continuation != nil }
    func requestAuthorization() async -> LocationAuthorization {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: LocationAuthorization) {
        authorization = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor ProbeStub: TunnelProbing {
    var requests = 0
    func check() async throws { requests += 1 }
}

private struct DetailProbe: TunnelProbing {
    static let detail = "timed out after 2.0s; last state waiting: POSIXErrorCode(rawValue: 50): Network is down"
    var lastFailureDetail: String? { Self.detail }
    func check() async throws { throw TunnelProbeFailure.timedOut }
}

private actor ControlledProbe: TunnelProbing {
    private var continuation: CheckedContinuation<Void, any Error>?
    var requests = 0
    var maximumConcurrent = 0
    private var concurrent = 0

    func check() async throws {
        requests += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ result: Result<Void, any Error> = .success(())) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
