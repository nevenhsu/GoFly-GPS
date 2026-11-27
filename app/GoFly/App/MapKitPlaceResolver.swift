import CoreLocation
import GoFlyCore
import MapKit

/// Enriches a selected point; the caller retains the exact tapped coordinate.
@MainActor
final class MapKitPlaceResolver: PlaceResolving {
    private let preferredLocale: @MainActor () -> Locale?

    init(preferredLocale: @escaping @MainActor () -> Locale? = {
        GoFlyPreferences.shared.language == .system ? nil : GoFlyPreferences.shared.locale
    }) {
        self.preferredLocale = preferredLocale
    }

    /// MapKit exposes address locale, not a per-map base-label language override.
    /// Read the preference for every new request, so switching language needs no map recreation.
    func makeRequest(at coordinate: GeoCoordinate) -> MKReverseGeocodingRequest? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(
            latitude: coordinate.latitude, longitude: coordinate.longitude
        )) else { return nil }
        request.preferredLocale = preferredLocale()
        return request
    }

    func resolve(at coordinate: GeoCoordinate) async throws -> MapPlace? {
        try Task.checkCancellation()
        guard let request = makeRequest(at: coordinate) else { return nil }
        let operation = ReversePlaceOperation(request: request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let items = try await operation.items()
            try Task.checkCancellation()
            guard let item = items.first else { return nil }
            let address = item.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = item.goFlyPlaceTitle(fallbackCoordinate: coordinate)
            return MapPlace(id: .coordinate(coordinate), title: title, coordinate: coordinate, address: address)
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
}

extension MKMapItem {
    /// International-aware concise place title:
    /// POI / landmark / store name → country-formatted short address (street/road) →
    /// city/district with context → city → region → full address → coordinate.
    func goFlyPlaceTitle(fallbackCoordinate: GeoCoordinate) -> String {
        let fullAddress = address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let distinctName = (rawName?.isEmpty == false && rawName != fullAddress) ? rawName : nil
        let candidates: [String?] = [
            distinctName,
            address?.shortAddress,
            addressRepresentations?.cityWithContext(.short),
            addressRepresentations?.cityName,
            addressRepresentations?.regionName,
            rawName,
            fullAddress
        ]
        for candidate in candidates {
            if let cleaned = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty {
                return cleaned
            }
        }
        return fallbackCoordinate.displayText
    }
}

@MainActor
private final class ReversePlaceOperation {
    private let request: MKReverseGeocodingRequest
    init(request: MKReverseGeocodingRequest) { self.request = request }
    func items() async throws -> [MKMapItem] { try await request.mapItems }
    func cancel() { request.cancel() }
}
