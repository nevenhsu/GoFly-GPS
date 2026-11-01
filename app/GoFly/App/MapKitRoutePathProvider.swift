import CoreLocation
import GoFlyCore
import MapKit

/// Directions planning never opens a device session or moves the phone.
@MainActor
final class MapKitRoutePathProvider: RoutePathProviding {
    func path(from start: GeoCoordinate, to end: GeoCoordinate,
              transport: RouteTransport) async throws -> [GeoCoordinate] {
        try Task.checkCancellation()
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        switch transport {
        case .automobile:
            request.transportType = .automobile
        case .walking:
            request.transportType = .walking
        case .transit:
            // Apple's SDK supports transit only for ETA, not route geometry. Keep the
            // requested final attempt; an unsupported response remains a planning failure.
            request.transportType = .transit
        }
        request.requestsAlternateRoutes = false
        let operation = MapKitDirectionsOperation(request: request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response: MKDirections.Response
            do {
                response = try await operation.calculate()
            } catch let error as MKError where error.code == .loadingThrottled {
                throw RoutePlanningThrottled(retryAfter: Self.timeUntilReset(error))
            }
            try Task.checkCancellation()
            guard let route = response.routes.first,
                  (2...10_000).contains(route.polyline.pointCount) else {
                throw RouteExecutionFailure.planningFailed
            }
            var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            let points = coordinates.compactMap { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            guard points.count == coordinates.count else { throw RouteExecutionFailure.invalidPath }
            return points
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
}

extension MapKitRoutePathProvider {
    /// Maps may say how long until requests are accepted again; otherwise wait 10 s.
    nonisolated static func timeUntilReset(_ error: MKError) -> Duration {
        func seconds(in info: [String: Any]) -> Double? {
            for (key, value) in info {
                if key.localizedCaseInsensitiveContains("timeUntilReset"), let number = value as? NSNumber {
                    return number.doubleValue
                }
                if let nested = value as? [String: Any], let found = seconds(in: nested) { return found }
            }
            return nil
        }
        let wait = seconds(in: error.userInfo).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 10
        return .milliseconds(Int(min(wait, 60) * 1000))
    }
}

@MainActor
private final class MapKitDirectionsOperation {
    private let directions: MKDirections
    init(request: MKDirections.Request) { directions = MKDirections(request: request) }
    func calculate() async throws -> MKDirections.Response { try await directions.calculate() }
    func cancel() { directions.cancel() }
}
