import Foundation

/// Maps refused a directions request because too many were sent recently.
/// The same request may succeed after `retryAfter`; it is not a planning failure.
public struct RoutePlanningThrottled: Error, Equatable, Sendable {
    public let retryAfter: Duration
    public init(retryAfter: Duration) { self.retryAfter = retryAfter }
}

/// Road legs already planned between two chosen places. Kept across launches
/// so reopening a route draws it without asking Maps again; a bounded file,
/// newest legs kept, and a missing or unreadable file is an empty cache.
@MainActor
public final class RouteLegCache {
    public static let maximumLegs = 48
    public static let maximumBytes = 4 << 20

    private struct Entry: Codable {
        let from: [Double]
        let to: [Double]
        let points: [[Double]]
    }
    private struct Document: Codable {
        var schemaVersion = 1
        var legs: [Entry]
    }

    private let file: AtomicFile?
    /// Oldest first.
    private var legs: [(from: GeoCoordinate, to: GeoCoordinate, route: PlannedRoute)] = []

    /// `file` nil keeps the cache in memory only.
    public init(file: AtomicFile?) {
        self.file = file
        guard let document = try? file?.loadJSON(Document.self), document.schemaVersion == 1 else { return }
        legs = document.legs.compactMap { entry in
            guard let from = Self.coordinate(entry.from), let to = Self.coordinate(entry.to),
                  let route = try? PlannedRoute(points: entry.points.compactMap(Self.coordinate)) else { return nil }
            return (from, to, route)
        }
    }

    public func leg(from: GeoCoordinate, to: GeoCoordinate) -> PlannedRoute? {
        legs.last { $0.from == from && $0.to == to }?.route
    }

    public func store(_ route: PlannedRoute, from: GeoCoordinate, to: GeoCoordinate) {
        legs.removeAll { $0.from == from && $0.to == to }
        legs.append((from, to, route))
        if legs.count > Self.maximumLegs { legs.removeFirst(legs.count - Self.maximumLegs) }
        save()
    }

    private func save() {
        guard let file else { return }
        let encoder = JSONEncoder()
        var entries = legs.map { Entry(from: [$0.from.latitude, $0.from.longitude], to: [$0.to.latitude, $0.to.longitude],
                                       points: $0.route.points.map { [$0.latitude, $0.longitude] }) }
        // Drop the oldest legs until the file fits; a cache write failure only costs a later request.
        while !entries.isEmpty {
            guard let data = try? encoder.encode(Document(legs: entries)) else { return }
            if data.count <= Self.maximumBytes { try? file.saveData(data); return }
            entries.removeFirst()
        }
    }

    private static func coordinate(_ pair: [Double]) -> GeoCoordinate? {
        pair.count == 2 ? GeoCoordinate(latitude: pair[0], longitude: pair[1]) : nil
    }
}
