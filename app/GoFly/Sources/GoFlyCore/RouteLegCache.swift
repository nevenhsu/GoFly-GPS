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
    public nonisolated static let maximumBytes = 4 << 20

    private struct Entry: Codable, Sendable {
        let from: [Double]
        let to: [Double]
        let points: [[Double]]
    }
    private struct Document: Codable, Sendable {
        var schemaVersion = 1
        var legs: [Entry]
    }

    private typealias Leg = (from: GeoCoordinate, to: GeoCoordinate, route: PlannedRoute)

    private actor Writer {
        let file: AtomicFile

        init(file: AtomicFile) { self.file = file }

        func save(_ legs: [Leg]) -> Bool {
            let encoder = JSONEncoder()
            var entries = legs.map {
                Entry(from: [$0.from.latitude, $0.from.longitude],
                      to: [$0.to.latitude, $0.to.longitude],
                      points: $0.route.points.map { [$0.latitude, $0.longitude] })
            }[...]
            while !entries.isEmpty {
                guard let data = try? encoder.encode(Document(legs: Array(entries))) else { return false }
                if data.count <= RouteLegCache.maximumBytes {
                    do { try file.saveData(data); return true }
                    catch { return false }
                }
                entries = entries.dropFirst()
            }
            return false
        }
    }

    private let writer: Writer?
    private var revision: UInt64 = 0
    private var writtenRevision: UInt64 = 0
    private var pending: (revision: UInt64, legs: [Leg])?
    private var draining = false
    private var waiters: [(revision: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    /// Oldest first.
    private var legs: [Leg] = []

    /// `file` nil keeps the cache in memory only.
    public init(file: AtomicFile?) {
        self.writer = file.map { Writer(file: $0) }
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
        guard let writer else { return }
        revision += 1
        pending = (revision, legs)
        guard !draining else { return }
        draining = true
        Task { await drain(using: writer) }
    }

    /// Waits for the current snapshot or one that supersedes it.
    @discardableResult
    public func flush() async -> Bool {
        if revision <= writtenRevision { return true }
        guard draining else { return false }
        let target = revision
        return await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
    }

    private func drain(using writer: Writer) async {
        while let job = pending {
            pending = nil
            let saved = await writer.save(job.legs)
            if saved { writtenRevision = job.revision }
            // A newer pending snapshot can still cover a failed write.
            if saved || pending == nil {
                let completed = waiters.filter { $0.revision <= job.revision }
                waiters.removeAll { $0.revision <= job.revision }
                for waiter in completed { waiter.continuation.resume(returning: saved) }
            }
        }
        draining = false
    }

    private static func coordinate(_ pair: [Double]) -> GeoCoordinate? {
        pair.count == 2 ? GeoCoordinate(latitude: pair[0], longitude: pair[1]) : nil
    }
}
