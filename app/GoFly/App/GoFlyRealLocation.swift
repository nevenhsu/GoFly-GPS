import Combine
import CoreLocation
import GoFlyCore

/// Opt-in, low-power real location. Fixes are one-shot requests at
/// hundred-meter accuracy, refreshed by `RealLocationRefresher` only while
/// they can be real. Creating this object never requests permission.
@MainActor
final class GoFlyRealLocation: NSObject, ObservableObject, CLLocationManagerDelegate, RealLocationFixRequesting {
    @Published private(set) var observation: RealLocationObservation?

    private let manager: CLLocationManager?
    private var awaitingPermission = false
    /// While set, continuous updates run so iOS produces a fresh fix instead of
    /// answering one-shot requests from a cache that still holds the simulated
    /// position. Ends at the first real fix, the deadline, or scene exit.
    private var streamDeadline: Task<Void, Never>?
    private lazy var refresher = RealLocationRefresher(source: self)
    /// Asked at most once per launch; iOS keeps a granted answer until the app leaves use.
    private var askedTemporaryFullAccuracy = false
    private static let temporaryFullAccuracyPurposeKey = "GoFlyRealLocationAfterSimulation"

    override init() {
        manager = CLLocationManager()
        super.init()
        configure(manager)
    }

#if DEBUG && targetEnvironment(simulator)
    init(uiTestFixture: Bool) {
        manager = uiTestFixture ? nil : CLLocationManager()
        super.init()
        configure(manager)
    }
#endif

    private func configure(_ manager: CLLocationManager?) {
        guard let manager else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if CLLocationManager.locationServicesEnabled(),
           manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            start()
        }
    }

    func start() {
        guard let manager else { return }
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = manager.location {
                publish(loc)
            }
            refresher.refreshNow()
        case .notDetermined, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func requestRecenter() {
        guard let manager else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            fail()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = manager.location {
                publish(loc)
            }
            refresher.refreshNow(waitingForRealFix: true)
            startStreaming(reason: "recenter")
        case .denied, .restricted:
            fail()
        @unknown default:
            fail()
        }
    }

    /// The scene is active again: retry real GPS and keep it fresh.
    func sceneDidBecomeActive() { refresher.sceneDidBecomeActive() }
    func sceneDidBecomeInactive() {
        refresher.sceneDidBecomeInactive()
        stopStreaming(reason: "inactive")
    }

    /// A confirmed GPS clear: the next fix can be real again.
    func refresh() {
        guard isAuthorized else { return }
        refresher.refreshNow(waitingForRealFix: true)
        startStreaming(reason: "clear")
    }

    private func startStreaming(reason: String) {
        guard let manager else { return }
        streamDeadline?.cancel()
        manager.startUpdatingLocation()
        Self.record("location.stream", ["event": .text("start"), "reason": .text(reason)])
        streamDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RealLocationRefresher.realFixWaitSeconds))
            guard !Task.isCancelled else { return }
            self?.stopStreaming(reason: "timeout")
        }
    }

    private func stopStreaming(reason: String) {
        guard let deadline = streamDeadline else { return }
        deadline.cancel()
        streamDeadline = nil
        manager?.stopUpdatingLocation()
        Self.record("location.stream", ["event": .text("stop"), "reason": .text(reason)])
    }

    private static func record(_ name: String, level: DiagnosticsLevel = .notice,
                               _ fields: [String: DiagnosticsField]) {
        Diagnostics.shared.record(name, category: .device, level: level, fields)
    }

    func requestFix() {
        guard isAuthorized else { return }
        guard let manager else { return }
        manager.requestLocation()
    }

    /// The system's last known real position, without requesting a new fix.
    /// Nil without authorization; simulated fixes fail the observation init.
    func cachedFix() -> RealLocationObservation? {
        guard isAuthorized, let location = manager?.location else { return nil }
        return Self.observation(from: location)
    }

    private var isAuthorized: Bool {
        guard let manager else { return false }
        return CLLocationManager.locationServicesEnabled()
            && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, let currentManager = self.manager else { return }
            if self.awaitingPermission, currentManager.authorizationStatus != .notDetermined {
                self.awaitingPermission = false
                self.requestRecenter()
            } else if currentManager.authorizationStatus == .authorizedWhenInUse || currentManager.authorizationStatus == .authorizedAlways {
                self.start()
                // Precise location granted while waiting: fetch a fresh real fix now.
                if self.streamDeadline != nil, currentManager.accuracyAuthorization == .fullAccuracy {
                    self.refresh()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let simulated = location.sourceInformation?.isSimulatedBySoftware == true
            // Routine 8 s fixes stay at debug; the post-clear wait is the useful part.
            let notable = simulated || self.streamDeadline != nil
            Self.record("location.fix", level: notable ? .notice : .debug, [
                "simulated": .flag(simulated),
                "age_s": .number(-location.timestamp.timeIntervalSinceNow, digits: 1),
                "acc_m": .number(location.horizontalAccuracy, digits: 0),
                "streaming": .flag(self.streamDeadline != nil)
            ])
            guard self.publish(location) else { return }
            self.refresher.fixReceived(simulated: simulated)
            if !simulated, self.currentObservation != nil {
                self.stopStreaming(reason: "realFix")
            }
            if simulated, self.streamDeadline != nil { self.requestTemporaryFullAccuracyIfReduced() }
        }
    }

    /// With approximate location iOS can keep serving the simulated place long
    /// after the simulation is cleared; precise location updates at once.
    /// Asked only while waiting for real GPS (after Stop or Recenter).
    private func requestTemporaryFullAccuracyIfReduced() {
        guard let manager, !askedTemporaryFullAccuracy,
              manager.accuracyAuthorization == .reducedAccuracy else { return }
        askedTemporaryFullAccuracy = true
        Self.record("location.fullAccuracy", ["event": .text("request")])
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.temporaryFullAccuracyPurposeKey) { error in
            let event = error == nil ? "answered" : "failed"
            Task { @MainActor in
                Self.record("location.fullAccuracy", ["event": .text(event)])
            }
        }
    }

    @discardableResult
    private func publish(_ location: CLLocation) -> Bool {
        if location.sourceInformation?.isSimulatedBySoftware == true,
           let currentObservation, location.timestamp < currentObservation.observedAt {
            // A delayed cached simulation cannot invalidate a newer real fix.
            Self.record("location.ignoredOlderSimulation", ["age_s": .number(-location.timestamp.timeIntervalSinceNow, digits: 1)])
            return false
        }
        observation = Self.observation(from: location)
        return true
    }

    private var currentObservation: RealLocationObservation? {
        guard let observation, (0...15).contains(Date().timeIntervalSince(observation.observedAt)) else { return nil }
        return observation
    }

    private static func observation(from location: CLLocation) -> RealLocationObservation? {
        RealLocationObservation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            observedAt: location.timestamp,
            isSoftwareSimulated: location.sourceInformation?.isSimulatedBySoftware == true
        )
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor [weak self] in
            Self.record("location.fail", ["code": .count(code)])
            self?.fail()
        }
    }

    /// A missing fix never shows a banner: indoor lack of GPS is normal in
    /// simulation, and the joystick origin hint covers the case that matters.
    private func fail() {
        observation = nil
    }

    func rejectedFix() {
        fail()
    }
}
