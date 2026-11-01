import Foundation

public struct RouteNodeID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
/// `empty` is an unset start or destination (Figma D1/D2): the row stays, the value is cleared.
public enum RouteNodeValue: Equatable, Sendable { case current, place(MapPlace), empty }
public enum RouteNodeRole: Equatable, Sendable { case start, waypoint(Int), destination }
public struct RouteNode: Identifiable, Equatable, Sendable {
    public let id: RouteNodeID
    public let value: RouteNodeValue
    public init(id: RouteNodeID = RouteNodeID(), value: RouteNodeValue) { self.id = id; self.value = value }
}
public struct RouteSpeed: Equatable, Sendable {
    public let kilometersPerHour: Int
    public var metersPerSecond: Double { Double(kilometersPerHour) / 3.6 }
    /// One speed preference for route, joystick and wander (Figma D7 presets).
    public static let standard = RouteSpeed(kilometersPerHour: 25)!
    public static let presets: [RouteSpeed] = [5, 25, 50, 100].compactMap { RouteSpeed(kilometersPerHour: $0) }
    public init?(kilometersPerHour: Int) {
        guard (1...120).contains(kilometersPerHour) else { return nil }
        self.kilometersPerHour = kilometersPerHour
    }
}
public enum RouteDraftSource: Equatable, Sendable {
    case manual([RouteNode])
    case gpx(GPXRouteSource)
}
public struct RouteDraft: Equatable, Sendable {
    public static let maximumNodeCount = 27
    public let source: RouteDraftSource
    public var nodes: [RouteNode] { if case .manual(let nodes) = source { return nodes }; return [] }
    public var gpxSource: GPXRouteSource? { if case .gpx(let source) = source { return source }; return nil }
    public var isManual: Bool { if case .manual = source { return true }; return false }
    /// Manual drafts can only be planned or started once start and destination hold a value.
    public var hasEmptyEndpoint: Bool {
        guard isManual else { return false }
        return nodes.count < 2 || nodes.first?.value == .empty || nodes.last?.value == .empty
    }
    public let speed: RouteSpeed
    public var start: RouteNode? { nodes.first }
    public var destination: RouteNode? { nodes.count >= 2 ? nodes.last : nil }
    public init(speed: RouteSpeed = .standard) {
        source = .manual([RouteNode(value: .current), RouteNode(value: .empty)]); self.speed = speed
    }
    public init?(start: RouteNodeValue? = .current, destination: RouteNodeValue?, speed: RouteSpeed = .standard) {
        self.init(values: [start, destination].compactMap { $0 }, speed: speed)
    }
    public init?(values: [RouteNodeValue], speed: RouteSpeed = .standard) {
        guard values.count <= Self.maximumNodeCount, values.filter({ $0 == .current }).count <= 1 else { return nil }
        source = .manual(values.map { RouteNode(value: $0) }); self.speed = speed
    }
    public init(imported: ImportedRouteSnapshot, speed: RouteSpeed = .standard) { self.init(gpx: imported.source, speed: speed) }
    public init(gpx: GPXRouteSource, speed: RouteSpeed = .standard) { source = .gpx(gpx); self.speed = speed }
    /// Rebuilds a manual draft while preserving the supplied node identities and order.
    ///
    /// This is intentionally failable: persisted drafts are input data and must pass the
    /// same limits as interactive edits before they can enter the live model.
    public init?(nodes: [RouteNode], speed: RouteSpeed = .standard) {
        guard nodes.count <= Self.maximumNodeCount,
              nodes.filter({ $0.value == .current }).count <= 1,
              Set(nodes.map(\.id)).count == nodes.count else { return nil }
        source = .manual(nodes)
        self.speed = speed
    }
    private init(source: RouteDraftSource, speed: RouteSpeed) { self.source = source; self.speed = speed }
    /// Whether a row's ✕ does anything: a stop is always deleted; the start
    /// and destination are cleared, and an empty destination row is deleted
    /// when a stop before it can become the destination.
    public func canRemove(nodeID id: RouteNodeID) -> Bool {
        guard isManual, let node = nodes.first(where: { $0.id == id }), let role = role(of: id) else { return false }
        switch role {
        case .waypoint: return true
        case .start: return node.value != .empty
        case .destination: return node.value != .empty || nodes.count > 2
        }
    }
    public func role(of id: RouteNodeID) -> RouteNodeRole? {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return nil }
        if index == 0 { return .start }
        return index == nodes.count - 1 ? .destination : .waypoint(index)
    }
    func replacing(nodeID: RouteNodeID, value: RouteNodeValue) -> RouteDraft? {
        guard isManual, let index = nodes.firstIndex(where: { $0.id == nodeID }),
              value != .current || !nodes.contains(where: { $0.id != nodeID && $0.value == .current }) else { return nil }
        var nodes = nodes
        nodes[index] = RouteNode(id: nodeID, value: value)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func inserting(nodeID: RouteNodeID, value: RouteNodeValue) -> RouteDraft? {
        guard isManual, nodes.count < Self.maximumNodeCount, !nodes.contains(where: { $0.id == nodeID }),
              value != .current || !nodes.contains(where: { $0.value == .current }) else { return nil }
        var nodes = nodes
        nodes.insert(RouteNode(id: nodeID, value: value), at: nodes.count)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func removing(nodeID: RouteNodeID) -> RouteDraft? {
        guard isManual, nodes.contains(where: { $0.id == nodeID }) else { return nil }
        return RouteDraft(nodes: nodes.filter { $0.id != nodeID }, speed: speed)
    }
    /// Clears the value of a start or destination node while keeping its row and identity.
    func clearing(nodeID: RouteNodeID) -> RouteDraft? {
        guard isManual, let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return nil }
        guard index == 0 || index == nodes.count - 1 else { return nil }
        var nodes = nodes
        nodes[index] = RouteNode(id: nodeID, value: .empty)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func moving(nodeID: RouteNodeID, toIndex: Int) -> RouteDraft? {
        guard isManual, nodes.indices.contains(toIndex), let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return nil }
        var nodes = nodes
        let node = nodes.remove(at: index)
        nodes.insert(node, at: toIndex)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    public func reversing() -> RouteDraft? {
        guard isManual, nodes.count >= 2 else { return nil }
        return RouteDraft(nodes: nodes.reversed(), speed: speed)
    }
    func resolvingCurrent(to coordinate: GeoCoordinate?) -> RouteDraft? {
        guard isManual else { return self }
        var resolved: [RouteNode] = []
        for node in nodes {
            if node.value == .current {
                guard let coordinate else { return nil }
                resolved.append(RouteNode(id: node.id, value: .place(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))))
            } else { resolved.append(node) }
        }
        return RouteDraft(nodes: resolved, speed: speed)
    }
    /// Planning input: unset rows are skipped and consecutive rows at the same coordinate
    /// become one stop. A run keeps its first row, except that it never replaces the destination.
    func mergingConsecutiveDuplicates() -> RouteDraft {
        guard isManual else { return self }
        func coordinate(_ node: RouteNode) -> GeoCoordinate? {
            if case .place(let place) = node.value { return place.coordinate }
            return nil
        }
        var merged: [RouteNode] = []
        for node in nodes where node.value != .empty {
            if let last = merged.last, let a = coordinate(last), a == coordinate(node) {
                if node.id == nodes.last?.id { merged[merged.count - 1] = node }
            } else { merged.append(node) }
        }
        return RouteDraft(nodes: merged, speed: speed) ?? self
    }
    func replacing(speed: RouteSpeed) -> RouteDraft { RouteDraft(source: source, speed: speed) }
}

public enum RouteExecutionPhase: String, Equatable, Sendable {
    case editing, planning, preparing, running, pausing, paused, cancelling, interrupted, unknown
}
public enum RouteHeading: String, Equatable, Sendable { case forward, reverse }
public enum RouteExecutionFailure: Error, Equatable, Sendable {
    case missingStart, missingDestination, currentLocationUnavailable, planningFailed, invalidPath
    case device(DeviceServiceFailure)
    case imported(ImportedRouteExecutionFailure)
    public var localizationKey: String {
        switch self {
        case .missingStart: "route.error.missingStart"
        case .missingDestination: "route.error.missingDestination"
        case .currentLocationUnavailable: "route.error.currentLocationUnavailable"
        case .planningFailed: "route.error.planningFailed"
        case .invalidPath: "route.error.invalidPath"
        case .device(let failure): failure.rawValue
        case .imported(let failure): failure.localizationKey
        }
    }
}
public struct RouteExecutionIntent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let lease: MovementTaskLease
    public let draft: RouteDraft
    public let route: PlannedRoute
    /// The only value a running route may change: the next step uses it.
    public internal(set) var speed: RouteSpeed
    public init(id: UUID = UUID(), lease: MovementTaskLease = MovementTaskLease(), draft: RouteDraft, route: PlannedRoute) {
        self.id = id; self.lease = lease; self.draft = draft; self.route = route; speed = draft.speed
    }
}
public struct RouteProgress: Equatable, Sendable {
    public let committedDistanceMeters: Double
    public let totalDistanceMeters: Double
    public let activeElapsed: Duration
    public let estimatedRemaining: Duration
    public var fraction: Double { committedDistanceMeters / totalDistanceMeters }
}
public struct RouteCompletion: Equatable, Sendable {
    public let executionID: UUID
    public let coordinate: GeoCoordinate
}
