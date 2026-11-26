import Combine
import Foundation
import GoFlyCore

@MainActor
final class GoFlyRecentPlaces: ObservableObject {
    private static let limit = 8
    private let file: AtomicFile?
    private var needsLoad = true
    @Published private(set) var places: [MapPlace] = []

    init(supportDirectory: URL?) {
        file = supportDirectory.map {
            AtomicFile(directory: $0.appendingPathComponent("RecentPlaces", isDirectory: true),
                       filename: "places.json", maximumBytes: 256 * 1024)
        }
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard needsLoad else { return }
        do {
            let saved = try file?.loadJSON([Entry].self) ?? []
            places = saved.prefix(Self.limit).compactMap(\.place)
            needsLoad = false
        } catch is DecodingError {
            // An unreadable archive can be replaced by the next selection.
            needsLoad = false
            Diagnostics.shared.record("search.recentLoadFailed", category: .device, level: .error)
        } catch {
            // Retry before recording so a transient read error cannot erase history.
            Diagnostics.shared.record("search.recentLoadFailed", category: .device, level: .error)
        }
    }

    func record(_ place: MapPlace) {
        loadIfNeeded()
        guard !needsLoad else { return }
        let updated = [place] + places.filter { $0.coordinate != place.coordinate }
        replace(with: Array(updated.prefix(Self.limit)))
    }

    func clear() {
        replace(with: [])
    }

    private func replace(with updated: [MapPlace]) {
        do {
            try file?.saveJSON(updated.map(Entry.init))
            needsLoad = false
            places = updated
        } catch {
            Diagnostics.shared.record("search.recentSaveFailed", category: .device, level: .error)
        }
    }

    private struct Entry: Codable {
        let latitude: Double
        let longitude: Double
        let mapKitID: String?
        let title: String
        let address: String?

        init(_ place: MapPlace) {
            latitude = place.coordinate.latitude
            longitude = place.coordinate.longitude
            if case let .mapKit(id) = place.id {
                mapKitID = id
            } else {
                mapKitID = nil
            }
            title = place.title
            address = place.address
        }

        var place: MapPlace? {
            guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            let id = mapKitID.map(PlaceIdentity.mapKit) ?? .coordinate(coordinate)
            return MapPlace(id: id, title: title, coordinate: coordinate, address: address)
        }
    }
}
