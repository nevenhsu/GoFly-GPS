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
    private lazy var refresher = RealLocationRefresher(source: self)

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
        case .denied, .restricted:
            fail()
        @unknown default:
            fail()
        }
    }

    /// The scene is active again: retry real GPS and keep it fresh.
    func sceneDidBecomeActive() { refresher.sceneDidBecomeActive() }
    func sceneDidBecomeInactive() { refresher.sceneDidBecomeInactive() }

    /// A confirmed GPS clear: the next fix can be real again.
    func refresh() {
        guard isAuthorized else { return }
        refresher.refreshNow(waitingForRealFix: true)
    }

    func requestFix() {
        guard isAuthorized else { return }
        guard let manager else { return }
        manager.requestLocation()
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
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publish(location)
            self.refresher.fixReceived(simulated: location.sourceInformation?.isSimulatedBySoftware == true)
        }
    }

    private func publish(_ location: CLLocation) {
        let observation = RealLocationObservation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            observedAt: location.timestamp,
            isSoftwareSimulated: location.sourceInformation?.isSimulatedBySoftware == true
        )
        self.observation = observation
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.fail() }
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
