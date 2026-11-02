import Foundation
import GoFlyCore
import GoFlyTransport

/// Simulator-only launch-argument overrides. Release and device builds compile
/// the inert variant, so no production argument can select test state.
#if DEBUG && targetEnvironment(simulator)
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func contains(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static var frame: String? {
        value("-gofly-ui-frame")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isFrameMode: Bool { frame != nil }
    static var isFirstLaunchFixture: Bool { contains("-gofly-ui-first-launch") }

    static var shouldExpireBackgroundContinuation: Bool { frame == "B8" || frame == "B9" }

    static var frameNeedsMapRuntime: Bool {
        guard let first = frame?.first else { return false }
        return ["B", "C", "D", "E", "F"].contains(String(first)) || frame == "R04"
    }

    static var fixturePlaces: [MapPlace] {
        [
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!),
                     title: "台北車站", coordinate: GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!,
                     address: "台北市中正區北平西路 3 號"),
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!),
                     title: "大安森林公園", coordinate: GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!,
                     address: "台北市大安區新生南路二段 1 號"),
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.06459, longitude: 121.52227)!),
                     title: "松山機場", coordinate: GeoCoordinate(latitude: 25.06459, longitude: 121.52227)!,
                     address: "台北市松山區敦化北路 340-9 號"),
        ]
    }

    static var favoriteRouteFixtures: [(label: String, places: [MapPlace])] {
        let routeData: [(String, String, String, Int, Double, Double, Double, Double)] = [
            ("通勤路線", "家", "台北 101", 8, 25.05712, 121.52281, 25.03396, 121.56447),
            ("每日晨跑", "大稻埕碼頭", "彩虹河濱", 4, 25.05620, 121.50880, 25.07110, 121.58880),
            ("週末騎行", "淡水捷運站", "漁人碼頭", 6, 25.16790, 121.44560, 25.18220, 121.41090),
            ("市區折返跑", "大安森林公園", "大稻埕公園", 12, 25.03389, 121.53530, 25.05910, 121.50930),
            ("信義區巡航", "台北車站", "象山站", 10, 25.04776, 121.51706, 25.02700, 121.57070),
            ("河濱單車道", "美堤河濱公園", "迎風公園", 5, 25.08080, 121.56790, 25.06610, 121.55200)
        ]
        return routeData.compactMap { label, startTitle, endTitle, count, startLat, startLon, endLat, endLon in
            guard let startCoordinate = GeoCoordinate(latitude: startLat, longitude: startLon),
                  let endCoordinate = GeoCoordinate(latitude: endLat, longitude: endLon) else { return nil }
            let places = (0..<count).compactMap { index -> MapPlace? in
                let fraction = Double(index) / Double(count - 1)
                guard let coordinate = GeoCoordinate(
                    latitude: startLat + (endLat - startLat) * fraction,
                    longitude: startLon + (endLon - startLon) * fraction
                ) else { return nil }
                let title = index == 0 ? startTitle : (index == count - 1 ? endTitle : "路線點位 \(index + 1)")
                return MapPlace(id: .coordinate(coordinate), title: title, coordinate: coordinate)
            }
            guard places.count == count,
                  places.first?.coordinate == startCoordinate,
                  places.last?.coordinate == endCoordinate else { return nil }
            return (label, places)
        }
    }

    static func favoritePlaceFixtures(frame: String) -> [MapPlace] {
        let entries: [(String, String?, Double, Double)] = [
            ("公司", "台北市信義區松仁路 100 號", 25.03312, 121.56789),
            ("測試點 A", "24.87721, 121.27947", 24.87721, 121.27947),
            ("台北車站", "台北市中正區北平西路 3 號", 25.04776, 121.51706),
            ("松山機場", "台北市松山區敦化北路 340 之 9 號", 25.06459, 121.52227),
            ("桃園高鐵站", "桃園市中壢區高鐵北路一段 6 號", 24.80870, 121.04090),
            ("淡水老街", "新北市淡水區中正路", 25.16952, 121.44077),
            ("24.200544, 121.348432", "台中市和平區", 24.200544, 121.348432)
        ]
        var places = entries.compactMap { entry -> MapPlace? in
            let (title, address, latitude, longitude) = entry
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return MapPlace(id: .coordinate(coordinate), title: title, coordinate: coordinate, address: address)
        }
        if frame == "C1" {
            let coordinate = GeoCoordinate(latitude: 24.000001, longitude: 120.000001)!
            places.append(MapPlace(id: .coordinate(coordinate), title: "測試用待刪除項目",
                                   coordinate: coordinate, address: "測試 fixture"))
        }
        return places
    }

    @MainActor
    static var searchCoordinateResult: MapPlace {
        let coordinate = GeoCoordinate(latitude: 25.04780, longitude: 121.51700)!
        return MapPlace(id: .coordinate(coordinate), title: goFlyString("figma.fixture.b4.coordinate"),
                        coordinate: coordinate)
    }

    @MainActor
    static var searchNearbyResults: [MapPlace] {
        let results: [(String, String, Double, Double)] = [
            ("figma.fixture.b4.result1.title", "figma.fixture.b4.result1.address", 25.04776, 121.51706),
            ("figma.fixture.b4.result2.title", "figma.fixture.b4.result2.address", 25.04850, 121.51820),
            ("figma.fixture.b4.result3.title", "figma.fixture.b4.result3.address", 25.04910, 121.51620),
            ("figma.fixture.b4.result4.title", "figma.fixture.b4.result4.address", 25.04630, 121.51570)
        ]
        return results.compactMap { result in
            let (titleKey, addressKey, latitude, longitude) = result
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return MapPlace(id: .coordinate(coordinate), title: goFlyString(titleKey), coordinate: coordinate,
                            address: goFlyString(addressKey))
        }
    }

    static func initialMode(for frame: String?) -> SessionMapMode? {
        guard let first = frame?.first else { return nil }
        if frame == "E5" { return .teleport }
        return switch first {
        case "D": .route
        case "E": .joystick
        case "B", "C", "F": .teleport
        default: nil
        }
    }

    @MainActor
    static func routeDraft(for frame: String?) -> RouteDraft? {
        guard let frame, frame.first == "D" else { return nil }
        let places = fixturePlaces
        let speed = RouteSpeed(kilometersPerHour: 25)!
        if frame == "D11" || frame == "D15" {
            let count = frame == "D15" ? 1_248 : 8
            let points = (0..<count).compactMap { index in
                if frame == "D15" {
                    let fraction = Double(index) / Double(count - 1)
                    return GeoCoordinate(latitude: 25.04776 + (25.03396 - 25.04776) * fraction,
                                         longitude: 121.51706 + (121.56447 - 121.51706) * fraction)
                }
                return GeoCoordinate(latitude: 25.04776 + Double(index) * 0.001,
                                     longitude: 121.51706 + Double(index) * 0.001)
            }
            guard let document = try? GPXDocument(content: .tracks([GPXTrack(segments: [points])])),
                  let source = try? GPXRouteSource(document: document,
                                                   displayFilename: frame == "D15" ? "台北市區.gpx" : "GoFly fixture.gpx") else { return nil }
            return RouteDraft(gpx: source, speed: speed)
        }
        let values: [RouteNodeValue]
        switch frame {
        case "D1": return RouteDraft(speed: speed)
        case "D2", "D2.a":
            let routePlaces = d2RoutePlaces
            // Keep the visual fixture independent of simulator GPS while
            // still rendering the current-location label and a planned path.
            values = [.place(d2CurrentLocation)] + routePlaces.map(RouteNodeValue.place)
        case "D3": values = [.place(places[0]), .place(places[1])]
        case "D8":
            let currentCoordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281)!
            let taipei101Coordinate = GeoCoordinate(latitude: 25.03396, longitude: 121.56447)!
            let currentLabel = MapPlace(id: .coordinate(currentCoordinate),
                                        title: goFlyString("route.currentLocation"),
                                        coordinate: currentCoordinate)
            let taipei101 = MapPlace(id: .coordinate(taipei101Coordinate),
                                     title: goFlyString("figma.fixture.route.taipei101"),
                                     coordinate: taipei101Coordinate)
            let destination = MapPlace(id: .coordinate(places[2].coordinate),
                                       title: goFlyString("route.chooseDestination"),
                                       coordinate: places[2].coordinate)
            values = [.place(currentLabel), .place(taipei101), .place(destination)]
        case "D23": values = [.current] + d23RoutePlaces.map(RouteNodeValue.place)
        case "D6", "D7", "D10", "D10.a": values = [.place(places[0]), .place(places[1])]
        case "D20": values = [.place(places[0]), .place(places[1])]
        default: values = [.current, .place(places[1])]
        }
        return RouteDraft(values: values, speed: speed)
    }

    @MainActor
    private static var d2RoutePlaces: [MapPlace] {
        let fixtures: [(String, Double, Double)] = [
            ("figma.fixture.route.taipei101", 25.03396, 121.56447),
            ("figma.fixture.route.palaceMuseum", 25.10236, 121.54850),
            ("figma.fixture.route.daanPark", 25.03389, 121.53530),
            ("figma.fixture.route.songshanAirport", 25.06970, 121.55230)
        ]
        return fixtures.compactMap { key, latitude, longitude in
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return MapPlace(id: .coordinate(coordinate), title: goFlyString(key), coordinate: coordinate)
        }
    }

    @MainActor
    private static var d23RoutePlaces: [MapPlace] {
        let fixtures: [(String, Double, Double)] = [
            ("figma.fixture.route.taipei101", 25.03396, 121.56447),
            ("figma.fixture.route.palaceMuseum", 25.10236, 121.54850),
            ("figma.fixture.route.daanPark", 25.03389, 121.53530),
            ("figma.fixture.route.huashan1914", 25.04426, 121.52970),
            ("figma.fixture.route.songshanAirport", 25.06970, 121.55230)
        ]
        return fixtures.compactMap { key, latitude, longitude in
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return MapPlace(id: .coordinate(coordinate), title: goFlyString(key), coordinate: coordinate)
        }
    }

    @MainActor
    private static var d2CurrentLocation: MapPlace {
        let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281)!
        return MapPlace(id: .coordinate(coordinate), title: goFlyString("route.currentLocation"),
                        coordinate: coordinate)
    }

    @MainActor
    static func onboardingController(for frame: String) -> OnboardingController {
        let location: LocationAuthorization = frame == "R03" ? .authorized : locationAuthorization
        return OnboardingController(
            probe: fixtureTunnelProbe(for: frame),
            location: fixtureLocationAuthorization(authorization: location),
            localNetwork: GoFlyLocalNetworkAuthorization.shared
        )
    }

    static func fixtureTunnelProbe(for frame: String? = nil) -> any TunnelProbing {
        GoFlyUITestTunnelProbe(isReachable: frame != "R04.a" && !contains("-gofly-ui-unreachable"),
                               holdOpen: frame == "B11")
    }

    static var routePlanOutcome: GoFlyUITestRoutePlanOutcome {
        GoFlyUITestRoutePlanOutcome(rawValue: value("-gofly-ui-route-outcome") ?? "success") ?? .success
    }

    static var locationAuthorization: LocationAuthorization {
        switch value("-gofly-ui-location-state") {
        case "authorized": .authorized
        case "denied": .denied
        default: .notDetermined
        }
    }

    @MainActor
    static func fixtureLocationAuthorization(
        authorization: LocationAuthorization = .notDetermined
    ) -> any LocationAuthorizing {
        GoFlyUITestLocationAuthorization(authorization: authorization)
    }

    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? {
        let namespace = value(flag).flatMap(UUID.init(uuidString:)) ?? (isFrameMode ? UUID() : nil)
        guard let namespace else { return nil }
        return root.appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(namespace.uuidString, isDirectory: true)
    }

    static func preferencesDefaults() -> UserDefaults? {
        let namespace = value("-gofly-ui-preferences-store").flatMap(UUID.init(uuidString:))
            ?? (isFrameMode ? UUID() : nil)
        guard let namespace,
              let store = UserDefaults(suiteName: "gofly.ui.preferences.\(namespace.uuidString)") else {
            return nil
        }
        if store.object(forKey: "gofly.preferences.v1") == nil {
            store.set([
                "language": value("-gofly-ui-preferences-language") ?? "system",
                "appearance": value("-gofly-ui-appearance")
                    ?? value("-gofly-ui-preferences-appearance") ?? "system",
                "backgroundRunSeconds": Int(value("-gofly-ui-background-seconds") ?? "43200") ?? 43200,
                "movementSpeed": Int(value("-gofly-ui-speed") ?? "25") ?? 25
            ], forKey: "gofly.preferences.v1")
        }
        return store
    }

    static func tunnelProbe() -> (any TunnelProbing)? {
        if contains("-gofly-ui-unreachable") { return GoFlyUITestTunnelProbe(isReachable: false) }
        if contains("-gofly-ui-reachable") { return GoFlyUITestTunnelProbe(isReachable: true) }
        return nil
    }
}

@MainActor
private final class GoFlyUITestLocationAuthorization: LocationAuthorizing {
    let authorization: LocationAuthorization

    init(authorization: LocationAuthorization) {
        self.authorization = authorization
    }

    func requestAuthorization() async -> LocationAuthorization { authorization }
}

private struct GoFlyUITestTunnelProbe: TunnelProbing {
    let isReachable: Bool
    var holdOpen = false
    var lastFailureDetail: String? { nil }

    func check() async throws {
        if holdOpen { try await Task.sleep(for: .seconds(120)) }
        if !isReachable { throw TunnelProbeFailure.unavailable }
    }
}

struct GoFlyUITestDeviceService: DeviceService {
    private var scenario: String { GoFlyUITestOverrides.value("-gofly-ui-device-state") ?? "normal" }

    func prepare() async throws {
        if scenario == "start-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func clearLocation() async throws {
        if scenario == "stop-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func resetClientConnection() async throws {
        if scenario == "reset-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func rebuildClientConnection() async throws {
        if scenario == "rebuild-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        if scenario == "unconfirmed-point" { return .unconfirmed(.operationTimedOut) }
        return .acknowledged
    }
}

@MainActor
final class GoFlyUITestContinuedProcessingDriver: ContinuedProcessingDriving {
    func register() -> Bool { true }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        onEvent(.launched(ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)))
        if GoFlyUITestOverrides.shouldExpireBackgroundContinuation {
            try? await Task.sleep(for: .milliseconds(250))
            onEvent(.expired(requestID: request.requestID))
        }
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        success ? .success : .failed
    }

    func cancel(requestID: UUID) {}
}

enum GoFlyUITestRoutePlanOutcome: String, Sendable {
    case success
    case planningFailed
    case reorderedSuccess
}

struct GoFlyUITestPlaceSearch: PlaceSearching {
    private let places = GoFlyUITestOverrides.fixturePlaces

    func search(query: String) async throws -> [MapPlace] {
        try Task.checkCancellation()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matching = places.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.address?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        return matching.isEmpty ? places : matching
    }
}

struct GoFlyUITestPlaceResolver: PlaceResolving {
    func resolve(at coordinate: GeoCoordinate) async throws -> MapPlace? {
        try Task.checkCancellation()
        if abs(coordinate.latitude - 25.04776) < 0.0001,
           abs(coordinate.longitude - 121.51706) < 0.0001 {
            return GoFlyUITestPlaceSearch().searchResult(named: "台北車站")
        }
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                        coordinate: coordinate, address: "fixture")
    }
}

extension GoFlyUITestPlaceSearch {
    fileprivate func searchResult(named title: String) -> MapPlace? {
        // Reuse the exact fixed record used by text search and the route picker.
        let coordinate = title == "台北車站"
            ? GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!
            : GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!
        return places.first { $0.coordinate == coordinate }
    }
}

struct GoFlyUITestRoutePlanner: RoutePlanning {
    let outcome: GoFlyUITestRoutePlanOutcome
    private let state: GoFlyUITestRoutePlannerState

    init(outcome: GoFlyUITestRoutePlanOutcome) {
        self.outcome = outcome
        state = GoFlyUITestRoutePlannerState()
    }

    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try Task.checkCancellation()
        if outcome == .planningFailed { throw RouteExecutionFailure.planningFailed }
        if outcome == .reorderedSuccess, await state.shouldFailInitialRequest() {
            throw RouteExecutionFailure.planningFailed
        }
        let midpoint = GeoCoordinate(latitude: (from.latitude + to.latitude) / 2,
                                     longitude: (from.longitude + to.longitude) / 2)!
        return [from, midpoint, to]
    }
}

private actor GoFlyUITestRoutePlannerState {
    private var didFailInitialRequest = false

    func shouldFailInitialRequest() -> Bool {
        guard !didFailInitialRequest else { return false }
        didFailInitialRequest = true
        return true
    }
}
#else
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? { nil }
    static func contains(_ flag: String) -> Bool { false }
    static var frame: String? { nil }
    static var isFrameMode: Bool { false }
    static var isFirstLaunchFixture: Bool { false }
    static var shouldExpireBackgroundContinuation: Bool { false }
    @MainActor
    static var searchCoordinateResult: MapPlace {
        let coordinate = GeoCoordinate(latitude: 25.04780, longitude: 121.51700)!
        return MapPlace(id: .coordinate(coordinate), title: goFlyString("figma.fixture.b4.coordinate"),
                        coordinate: coordinate)
    }
    @MainActor static var searchNearbyResults: [MapPlace] { [] }
    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? { nil }
    static func preferencesDefaults() -> UserDefaults? { nil }
    static func tunnelProbe() -> (any TunnelProbing)? { nil }
}
#endif
