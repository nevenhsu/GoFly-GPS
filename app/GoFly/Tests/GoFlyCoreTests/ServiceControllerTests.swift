import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ServiceControllerTests {
    @Test func startupPreparesServiceWithoutClearingOrClaimingGPS() async throws {
        let device = TestDevice()
        let controller = ServiceController(service: device)
        #expect(controller.clearState == .unknown)
        #expect(controller.start())
        await settle(controller)
        #expect(controller.phase == .ready)
        #expect(controller.clearState == .unknown)
        #expect(controller.realLocation == nil)
        #expect(await device.operations == ["prepare"])
    }

    @Test func stopDuringPreparationQueuesClearAndRejectsNewOperations() async throws {
        let device = ControlledDevice()
        let controller = ServiceController(service: device)
        #expect(controller.start())
        await device.waitForPrepare()
        #expect(controller.stop())
        #expect(!controller.start())
        #expect(!controller.restoreGPS())
        #expect(!controller.stop())
        #expect(controller.clearState == .pending)
        #expect(await device.operations == ["prepare"])
        await device.finishPrepare()
        await device.waitForClear()
        #expect(controller.phase == .stopping)
        #expect(!controller.canStart)
        await device.finishClear()
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .confirmed)
        #expect(controller.gpsStatusKey == "gps.clearedWaiting")
        #expect(await device.operations == ["prepare", "clear"])
    }

    @Test func resetAppearsOnlyAfterStopFailsAndEndsWithoutAnError() async throws {
        let device = SwitchableDevice()
        let controller = ServiceController(service: device)
        #expect(!controller.canForceReset)
        #expect(controller.start())
        await settle(controller)
        #expect(!controller.canForceReset)
        await device.setFailure(.tunnelUnavailable)
        #expect(controller.stop())
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.error == .tunnelUnavailable)
        #expect(controller.canForceReset)

        #expect(controller.forceReset())
        #expect(!controller.canForceReset)
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.error == nil)
        #expect(controller.clearState == .unknown)
        #expect(controller.canForceReset)

        await device.setFailure(nil)
        #expect(controller.forceReset())
        await settle(controller)
        #expect(controller.error == nil)
        #expect(controller.clearState == .confirmed)
        #expect(!controller.canForceReset)
        #expect(await device.operations == ["prepare", "clear", "reset", "clear", "reset", "clear"])
    }

    @Test func startRebuildsTheConnectionOnlyAfterALeftoverOrFailedAttempt() async throws {
        let device = SwitchableDevice()
        let controller = ServiceController(service: device)
        #expect(controller.start())
        await settle(controller)
        await device.setFailure(.tunnelUnavailable)
        #expect(controller.stop())
        await settle(controller)
        await device.setFailure(nil)
        #expect(controller.start())
        await settle(controller)
        #expect(controller.phase == .ready)
        #expect(await device.operations == ["prepare", "clear", "reset", "prepare"])

        #expect(controller.stop())
        await settle(controller)
        #expect(controller.clearState == .confirmed)
        #expect(controller.start())
        await settle(controller)
        #expect(await device.operations.suffix(2) == ["clear", "prepare"])
    }

    @Test func startAfterStopClearsTheStoppedFlagSoTheSessionShowsStarted() async throws {
        let device = SwitchableDevice()
        let controller = ServiceController(service: device)
        #expect(controller.start())
        await settle(controller)
        controller.stopSimulation()
        #expect(controller.stop())
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.start())
        await settle(controller)
        #expect(controller.phase == .ready)
        #expect(!controller.hasSimulated)
    }

    @Test func timeoutCannotUnlockNativeWorkOrSkipMandatoryClear() async throws {
        let device = ControlledDevice()
        let clock = ManualServiceWatchdog()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(20), watchdogSleep: clock.sleep)
        #expect(controller.start())
        await device.waitForPrepare()
        await wait { clock.requests.count == 1 }
        clock.fireLatest()
        await wait { controller.phase == .repairRequired }
        #expect(controller.nativeBusy)
        #expect(!controller.start())
        #expect(!controller.restoreGPS())
        #expect(controller.stop())
        await wait { clock.requests.count == 2 }
        clock.fireLatest()
        await wait { controller.phase == .repairRequired }
        #expect(controller.nativeBusy)
        #expect(!controller.stop())
        await device.finishPrepare()
        await device.waitForClear()
        #expect(!controller.start())
        await device.finishClear()
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.error == .operationTimedOut)
        #expect(controller.clearState == .unknown)
        #expect(controller.canRestoreGPS)
        #expect(await device.operations == ["prepare", "clear"])
    }

    @Test func clearFailureLeavesServiceStoppedAndRepairAvailable() async throws {
        let device = TestDevice(failure: .tunnelUnavailable)
        let controller = ServiceController(service: device)
        #expect(controller.restoreGPS())
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .unknown)
        #expect(controller.error == .tunnelUnavailable)
        #expect(controller.statusKey == "service.stoppedGPSPending")
        #expect(controller.canStart && controller.canRestoreGPS)
    }

    @Test(arguments: ["stop", "restore"])
    func confirmedGPSMarkerSurvivesServiceRepairCommands(command: String) async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(), now: { now })
        if command == "stop" {
            #expect(controller.start())
            await settle(controller)
        }
        let fix = RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-1))
        controller.observeRealLocation(fix)
        #expect(controller.positionMarker?.coordinate == fix?.coordinate)
        #expect(controller.positionMarker?.freshness == .fresh)
        if command == "stop" { #expect(controller.stop()) } else { #expect(controller.restoreGPS()) }
        #expect(controller.positionMarker?.coordinate == fix?.coordinate, "A service command must not remove the last confirmed map marker")
        #expect(controller.positionMarker?.freshness == .waiting)
        await settle(controller)
        #expect(controller.positionMarker?.coordinate == fix?.coordinate)
        #expect(controller.realLocation == nil)
        #expect(controller.gpsStatusKey == "gps.clearedWaiting")
    }

    @Test func invalidGPSPreservesWaitingMarkerUntilNewValidObservation() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(), now: { now })
        controller.observeRealLocation(nil)
        #expect(controller.positionMarker == nil)
        let fix = RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-1))
        controller.observeRealLocation(fix)
        let rejected: [RealLocationObservation?] = [
            nil,
            RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-30)),
            RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: 5, observedAt: now.addingTimeInterval(1)),
            RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: -1, observedAt: now),
            RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: 5, observedAt: now, isSoftwareSimulated: true),
        ]
        for sample in rejected {
            controller.observeRealLocation(sample)
            #expect(controller.realLocation == nil)
            #expect(controller.positionMarker?.coordinate == fix?.coordinate)
            #expect(controller.positionMarker?.freshness == .waiting)
        }
        #expect(controller.restoreGPS())
        await settle(controller)
        #expect(controller.gpsStatusKey == "gps.clearedWaiting")
        let current = RealLocationObservation(latitude: 26, longitude: 122,
            horizontalAccuracy: 5, observedAt: now)
        controller.observeRealLocation(current)
        #expect(controller.positionMarker?.coordinate == current?.coordinate)
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.gpsStatusKey == "gps.observed")
    }

    @Test func failedRestorePreservesOnlyWaitingDisplayMarker() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(failure: .tunnelUnavailable), now: { now })
        let fix = RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 5, observedAt: now)
        controller.observeRealLocation(fix)
        #expect(controller.restoreGPS())
        await settle(controller)
        #expect(controller.positionMarker?.coordinate == fix?.coordinate)
        #expect(controller.positionMarker?.freshness == .waiting)
        #expect(controller.realLocation == nil)
        #expect(controller.clearState == .unknown)
        #expect(controller.gpsStatusKey == "gps.unknown")
    }

    @Test func freshMarkerBeforeClearAcknowledgementDoesNotProveRecovery() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let device = ControlledDevice()
        let controller = ServiceController(service: device, now: { now })
        #expect(controller.restoreGPS())
        await device.waitForClear()
        let beforeClear = RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-1))
        controller.observeRealLocation(beforeClear)
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.gpsStatusKey == "gps.clearing")
        await device.finishClear()
        await settle(controller)
        #expect(controller.positionMarker?.coordinate == beforeClear?.coordinate)
        #expect(controller.gpsStatusKey == "gps.clearedWaiting")
        controller.observeRealLocation(RealLocationObservation(latitude: 26, longitude: 122,
            horizontalAccuracy: 5, observedAt: now))
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.gpsStatusKey == "gps.observed")
    }

    @Test func timedOutRestoreAlreadyOwnsTheOnlySafetyClear() async throws {
        let device = ControlledDevice()
        let clock = ManualServiceWatchdog()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(20), watchdogSleep: clock.sleep)
        #expect(controller.restoreGPS())
        await device.waitForClear()
        await wait { clock.requests.count == 1 }
        clock.fireLatest()
        await wait { controller.phase == .repairRequired }
        #expect(!controller.stop())
        #expect(!controller.start())
        await device.finishClear()
        await settle(controller)
        #expect(await device.operations == ["clear"])
        #expect(controller.clearState == .unknown)
    }

    @Test func validGPSIsIndependentOfClearAcknowledgement() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(failure: .tunnelUnavailable), now: { now })
        let observation = RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now)
        controller.observeRealLocation(observation)
        #expect(controller.realLocation == observation)
        #expect(controller.clearState == .unknown)
        #expect(controller.gpsStatusKey == "gps.unknown")
        #expect(controller.restoreGPS())
        await settle(controller)
        controller.observeRealLocation(observation)
        #expect(controller.realLocation == observation)
        #expect(controller.clearState == .unknown)
    }

    @Test func staleOrSimulatedGPSDoesNotProveRestoration() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(), now: { now })
        #expect(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 5,
                                       observedAt: now, isSoftwareSimulated: true) == nil)
        #expect(controller.restoreGPS())
        await settle(controller)
        controller.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-30)))
        #expect(controller.realLocation == nil)
        controller.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now))
        #expect(controller.gpsStatusKey == "gps.observed")
        #expect(controller.clearState == .confirmed)
        #expect(controller.realLocation?.latitude == 25)
    }

    private func wait(_ predicate: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(predicate())
    }

    private func settle(_ controller: ServiceController) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while controller.nativeBusy && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(!controller.nativeBusy)
    }
}

private actor TestDevice: DeviceService {
    var operations: [String] = []
    let failure: DeviceServiceFailure?
    init(failure: DeviceServiceFailure? = nil) { self.failure = failure }
    func prepare() async throws { operations.append("prepare"); try failIfNeeded() }
    func clearLocation() async throws { operations.append("clear"); try failIfNeeded() }
    func resetClientConnection() async throws { operations.append("reset"); try failIfNeeded() }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome { .notSent(.deviceRequired) }
    private func failIfNeeded() throws { if let failure { throw failure } }
}

private actor ControlledDevice: DeviceService {
    var operations: [String] = []
    private var preparation: CheckedContinuation<Void, Never>?
    private var clearing: CheckedContinuation<Void, Never>?
    func prepare() async throws {
        operations.append("prepare")
        await withCheckedContinuation { preparation = $0 }
    }
    func clearLocation() async throws {
        operations.append("clear")
        await withCheckedContinuation { clearing = $0 }
    }
    func resetClientConnection() async throws { operations.append("reset") }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome { .notSent(.deviceRequired) }
    func finishPrepare() { preparation?.resume(); preparation = nil }
    func finishClear() { clearing?.resume(); clearing = nil }
    func waitForPrepare() async { while preparation == nil { await Task.yield() } }
    func waitForClear() async { while clearing == nil { await Task.yield() } }
}

private actor SwitchableDevice: DeviceService {
    var operations: [String] = []
    private var failure: DeviceServiceFailure?
    func setFailure(_ failure: DeviceServiceFailure?) { self.failure = failure }
    func prepare() async throws { operations.append("prepare"); try failIfNeeded() }
    func clearLocation() async throws { operations.append("clear"); try failIfNeeded() }
    func resetClientConnection() async throws { operations.append("reset"); try failIfNeeded() }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome { .notSent(.deviceRequired) }
    private func failIfNeeded() throws { if let failure { throw failure } }
}
