import GoFlyCore
import GoFlyTransport
import SwiftUI

/// Retains the normal runtime owners for the lifetime of the App scene after
/// setup bootstrap admits ordinary or completed startup.
@MainActor
final class GoFlyRuntimeAssembly: ObservableObject {
    let service: ServiceController
    let sessionRecovery: SessionRecoveryStore
    let movement: GoFlyMovementModel
    let favorites: FavoritePlacesStore
    let importedRoutes: ImportedRoutesStore
    let favoriteRoutes: FavoriteRoutesStore
    let onboarding: OnboardingController

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recovery = goFlySessionRecoveryStore()
        let service: ServiceController
        #if DEBUG && targetEnvironment(simulator)
        let isUITestFixture = GoFlyUITestOverrides.isFrameMode || GoFlyUITestOverrides.isFirstLaunchFixture
        let device: any DeviceService = isUITestFixture ? GoFlyUITestDeviceService() : NativeDeviceService()
        service = ServiceController(service: device)
        #else
        let isUITestFixture = false
        let device: any DeviceService = NativeDeviceService()
        service = ServiceController(service: device)
        #endif
        // The DDI modal activates support through the same device boundary.
        GoFlySupportPreparation.shared.device = device
        let snapshot = recovery.initialSnapshot
        let restoredPosition: SessionDisplayPosition?
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture, GoFlyUITestOverrides.frameNeedsMapRuntime,
           let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) {
            restoredPosition = SessionDisplayPosition(coordinate: coordinate, source: .simulation)
        } else {
            restoredPosition = snapshot.position
        }
#else
        restoredPosition = snapshot.position
#endif
        _ = service.restoreColdRecovery(position: restoredPosition)
        if snapshot.activeMovement != nil || snapshot.uncertainty != nil {
            service.markColdClearPending()
            _ = service.beginColdClear()
        }

        self.service = service
        self.sessionRecovery = recovery
        // UI-test fixtures plan with a scripted planner; keep their legs out of the real cache.
        let routeLegs = RouteLegCache(file: isUITestFixture ? nil : AtomicFile(
            directory: support.appendingPathComponent("RouteLegCache", isDirectory: true),
            filename: "legs.json", maximumBytes: RouteLegCache.maximumBytes))
        self.movement = GoFlyMovementModel(service: service, recoveryStore: recovery, routeLegs: routeLegs)
        self.favorites = Self.favoritePlacesStore(
            directory: support.appendingPathComponent("FavoritePlaces", isDirectory: true),
            allowUITestNamespace: true)
        self.importedRoutes = Self.importedRoutesStore(
            directory: support.appendingPathComponent("ImportedRoutes", isDirectory: true),
            allowUITestNamespace: true)
        self.favoriteRoutes = Self.favoriteRoutesStore(
            directory: support.appendingPathComponent("FavoriteRoutes", isDirectory: true),
            allowUITestNamespace: true)
        self.onboarding = OnboardingController(
            probe: Self.onboardingProbe(isUITestFixture: isUITestFixture),
            location: Self.onboardingLocationAuthorization(isUITestFixture: isUITestFixture),
            localNetwork: GoFlyLocalNetworkAuthorization.shared
        )
        self.movement.observeDataErrors(recoveryStore: recovery, favorites: favorites,
            importedRoutes: importedRoutes, favoriteRoutes: favoriteRoutes)
    }

#if DEBUG && targetEnvironment(simulator)
    func prepareUITestData() async {
        guard GoFlyUITestOverrides.isFrameMode else { return }
        let places = GoFlyUITestOverrides.fixturePlaces
        let frame = GoFlyUITestOverrides.frame ?? ""
        if favorites.favorites.isEmpty, ["C1", "C2", "C3", "C4"].contains(frame) {
            for place in GoFlyUITestOverrides.favoritePlaceFixtures(frame: frame).reversed() {
                _ = favorites.save(place: place, label: nil)
            }
        } else if favorites.favorites.isEmpty, frame == "B2" {
            _ = favorites.save(place: places[2], label: "測試點 A")
            _ = favorites.save(place: places[0], label: "公司")
        }

        await importedRoutes.load()
        if importedRoutes.records.isEmpty {
            for (filename, count, latitudeStep, longitudeStep) in [
                ("通勤.gpx", 8, 0.0009, 0.0005),
                ("河濱路線.gpx", 436, 0.0007, 0.0011),
                ("台北市區.gpx", 1_248, 0.001, 0.001)
            ] {
                let points = (0..<count).compactMap { index in
                    GeoCoordinate(latitude: 25.04776 + Double(index) * latitudeStep,
                                  longitude: 121.51706 + Double(index) * longitudeStep)
                }
                if let document = try? GPXDocument(content: .tracks([GPXTrack(segments: [points])])),
                   let data = try? GPXCodec.encode(document, name: filename) {
                    _ = await importedRoutes.importData(data, filename: filename)
                }
            }
        }

        await favoriteRoutes.load()
        if favoriteRoutes.records.isEmpty,
           ["D19", "D20", "D21", "D22"].contains(GoFlyUITestOverrides.frame ?? "") {
            for fixture in GoFlyUITestOverrides.favoriteRouteFixtures {
                guard let draft = RouteDraft(values: fixture.places.map(RouteNodeValue.place)),
                      let candidate = try? FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil) else { continue }
                _ = await favoriteRoutes.save(candidate, label: fixture.label)
            }
        }
    }
#endif

    func captureCurrentRecoverySnapshotAndFlush() async -> Bool {
        let snapshot = movement.recovery.snapshot(mode: movement.presentationMode)
        guard sessionRecovery.capture(snapshot) else { return false }
        return await sessionRecovery.flush()
    }

    private static func favoritePlacesStore(directory: URL, allowUITestNamespace: Bool) -> FavoritePlacesStore {
        var resolved = directory
#if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace {
            resolved = GoFlyUITestOverrides.namespace(
                "-gofly-ui-favorites-store",
                under: directory.deletingLastPathComponent(),
                folder: "FavoritePlaces"
            ) ?? directory
        }
#endif
        return FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: resolved))
    }

    private static func importedRoutesStore(directory: URL, allowUITestNamespace: Bool) -> ImportedRoutesStore {
        var resolved = directory
#if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace {
            resolved = GoFlyUITestOverrides.namespace(
                "-gofly-ui-imports-store",
                under: directory.deletingLastPathComponent(),
                folder: "ImportedRoutes"
            ) ?? directory
        }
#endif
        return ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: resolved))
    }

    private static func favoriteRoutesStore(directory: URL, allowUITestNamespace: Bool) -> FavoriteRoutesStore {
        var resolved = directory
#if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace {
            resolved = GoFlyUITestOverrides.namespace(
                "-gofly-ui-favorite-routes-store",
                under: directory.deletingLastPathComponent(),
                folder: "FavoriteRoutes"
            ) ?? directory
        }
#endif
        return FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: resolved))
    }

    private static func onboardingProbe(isUITestFixture: Bool) -> any TunnelProbing {
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture { return GoFlyUITestOverrides.fixtureTunnelProbe(for: GoFlyUITestOverrides.frame) }
#endif
        return GoFlyUITestOverrides.tunnelProbe() ?? NetworkTunnelProbe()
    }

    private static func onboardingLocationAuthorization(isUITestFixture: Bool) -> any LocationAuthorizing {
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture { return GoFlyUITestOverrides.fixtureLocationAuthorization() }
#endif
        return GoFlyLocationAuthorization()
    }
}

private struct UnavailableFavoritePlacesPersistence: FavoritePlacesPersistence {
    func read() throws -> Data? { throw FavoritePlacesFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw FavoritePlacesFailure.unavailable }
}
