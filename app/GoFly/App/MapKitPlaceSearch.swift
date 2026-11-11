import GoFlyCore
import MapKit

@MainActor
enum MapKitSearchRegionContext {
    static var current: MKCoordinateRegion?
}

@MainActor
final class MapKitPlaceSearch: PlaceSearching {
    /// Place search first; when nothing matches, retry without a leading postal code and
    /// finally as a plain address geocode, which handles street addresses MKLocalSearch misses.
    func search(query: String) async throws -> [MapPlace] {
        let places = try await localSearch(query)
        if !places.isEmpty { return places }
        let stripped = AddressQuery.withoutPostalCode(query)
        if let stripped {
            let retried = try await localSearch(stripped)
            if !retried.isEmpty { return retried }
        }
        return try await geocode(stripped ?? query)
    }

    private func localSearch(_ query: String) async throws -> [MapPlace] {
        try Task.checkCancellation()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = MapKitSearchRegionContext.current {
            request.region = region
        }
        let operation = MapKitSearchOperation(request: request)
        return try await withTaskCancellationHandler {
            let items = try await Self.treatingNotFoundAsEmpty { try await operation.start().mapItems }
            try Task.checkCancellation()
            return Self.mapPlaces(from: items)
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }

    private func geocode(_ address: String) async throws -> [MapPlace] {
        try Task.checkCancellation()
        guard let request = MKGeocodingRequest(addressString: address) else { return [] }
        if let region = MapKitSearchRegionContext.current {
            request.region = region
        }
        let operation = MapKitGeocodeOperation(request: request)
        return try await withTaskCancellationHandler {
            let items = try await Self.treatingNotFoundAsEmpty { try await operation.items() }
            try Task.checkCancellation()
            return Self.mapPlaces(from: items)
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }

    private static func treatingNotFoundAsEmpty(
        _ body: () async throws -> [MKMapItem]
    ) async throws -> [MKMapItem] {
        do {
            return try await body()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    private static func mapPlaces(from items: [MKMapItem]) -> [MapPlace] {
        var seen: Set<PlaceIdentity> = []
        return items.compactMap { item in
            guard let coordinate = GeoCoordinate(
                latitude: item.location.coordinate.latitude,
                longitude: item.location.coordinate.longitude
            ) else { return nil }
            let identity = item.identifier.map { PlaceIdentity.mapKit($0.rawValue) }
                ?? .coordinate(coordinate)
            guard seen.insert(identity).inserted else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = item.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [name, address].compactMap { $0 }.first { !$0.isEmpty } ?? coordinate.displayText
            return MapPlace(id: identity, title: title, coordinate: coordinate, address: address)
        }
    }
}

/// Keeps the non-Sendable MapKit request on one actor, including cancellation.
@MainActor
private final class MapKitSearchOperation {
    private let search: MKLocalSearch
    init(request: MKLocalSearch.Request) { search = MKLocalSearch(request: request) }
    func start() async throws -> MKLocalSearch.Response { try await search.start() }
    func cancel() { search.cancel() }
}

@MainActor
private final class MapKitGeocodeOperation {
    private let request: MKGeocodingRequest
    init(request: MKGeocodingRequest) { self.request = request }
    func items() async throws -> [MKMapItem] { try await request.mapItems }
    func cancel() { request.cancel() }
}
