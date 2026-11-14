import Foundation

public enum SessionRecoveryLimits {
    public static let schemaVersion = 1
    public static let recordBytes = 4 * 1_024 * 1_024
    public static let inputGPXBytes = GPXLimits.fileBytes
    public static let manualNodes = RouteDraft.maximumNodeCount
    public static let gpxPoints = GPXLimits.points
    public static let activePathPoints = 10_000
    public static let historyPoints = 100
    public static let durationSeconds: Int64 = 365 * 24 * 60 * 60
}

/// Versioned, bounded JSON for the complete data-only recovery checkpoint.
/// Runtime models deliberately stay free of Codable concerns and native identity.
public enum SessionRecoveryCodec {
    public static func encode(_ snapshot: SessionRecoverySnapshot) throws -> Data {
        try encode(snapshot, revision: 0)
    }

    public static func encode(_ snapshot: SessionRecoverySnapshot, revision: UInt64) throws -> Data {
        try encode(snapshot, revision: revision, encodeGPX: { try GPXCodec.encode($0) })
    }

    static func encode(_ snapshot: SessionRecoverySnapshot, revision: UInt64,
                       encodeGPX: (GPXDocument) throws -> Data) throws -> Data {
        do {
            try validateSnapshot(snapshot)
            let archive = try Archive(snapshot: snapshot, revision: revision, encodeGPX: encodeGPX)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(archive)
            guard data.count <= SessionRecoveryLimits.recordBytes else { throw SessionRecoveryFailure.limitExceeded }
            return data
        } catch let failure as SessionRecoveryFailure {
            throw failure
        } catch let failure as GPXFailure {
            switch failure {
            case .sizeLimitExceeded, .pointLimitExceeded, .resourceLimitExceeded:
                throw SessionRecoveryFailure.limitExceeded
            default:
                throw SessionRecoveryFailure.invalidSnapshot
            }
        } catch {
            throw SessionRecoveryFailure.invalidSnapshot
        }
    }

    public static func decode(_ data: Data) throws -> SessionRecoverySnapshot {
        try decodeRecord(data).snapshot
    }

    public static func decodeRecord(_ data: Data) throws -> (snapshot: SessionRecoverySnapshot, revision: UInt64) {
        guard data.count <= SessionRecoveryLimits.recordBytes else { throw SessionRecoveryFailure.limitExceeded }
        let decoder = JSONDecoder()
        let version: Version
        do { version = try decoder.decode(Version.self, from: data) }
        catch { throw SessionRecoveryFailure.corruptArchive }
        guard version.schemaVersion == SessionRecoveryLimits.schemaVersion else {
            throw SessionRecoveryFailure.unsupportedSchema
        }
        let archive: Archive
        do { archive = try decoder.decode(Archive.self, from: data) }
        catch { throw SessionRecoveryFailure.corruptArchive }
        do {
            let decoded = try archive.snapshot()
            let snapshot = decoded.snapshot
            try validateSnapshot(snapshot)
            return decoded
        } catch let failure as SessionRecoveryFailure {
            throw failure
        } catch {
            throw SessionRecoveryFailure.corruptArchive
        }
    }

    /// The fields in Archive. Runtime history and uncertainty are not serialized.
    static func samePersistentContent(_ lhs: SessionRecoverySnapshot, _ rhs: SessionRecoverySnapshot) -> Bool {
        lhs.mode == rhs.mode && lhs.roundTripEnabled == rhs.roundTripEnabled
            && lhs.joystickSpeed == rhs.joystickSpeed && lhs.position == rhs.position
            && lhs.draft == rhs.draft
    }

    static func validateSnapshot(_ snapshot: SessionRecoverySnapshot) throws {
        guard snapshot.draft.speed.kilometersPerHour >= 2,
              snapshot.joystickSpeed.kilometersPerHour >= 2 else { throw SessionRecoveryFailure.invalidSnapshot }
        try validate(snapshot.draft)
        if let position = snapshot.position { try validate(position.coordinate) }
    }

    private static func validate(_ draft: RouteDraft) throws {
        guard draft.speed.kilometersPerHour >= 2 else { throw SessionRecoveryFailure.invalidSnapshot }
        switch draft.source {
        case .manual(let nodes):
            guard nodes.count <= SessionRecoveryLimits.manualNodes,
                  nodes.filter({ $0.value == .current }).count <= 1,
                  Set(nodes.map(\.id)).count == nodes.count else { throw SessionRecoveryFailure.invalidSnapshot }
            for node in nodes {
                if case .place(let place) = node.value { try validate(place) }
            }
        case .gpx(let source):
            guard source.document.pointCount <= SessionRecoveryLimits.gpxPoints,
                  GPXRouteSource.validDisplayFilename(source.displayFilename) else {
                throw SessionRecoveryFailure.invalidSnapshot
            }
        }
    }

    private static func validate(_ place: MapPlace) throws {
        guard FavoritePlacesArchive.validText(place.title, maximum: FavoritePlacesLimits.titleCharacters),
              !place.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              place.address.map({ FavoritePlacesArchive.validText($0, maximum: FavoritePlacesLimits.addressCharacters) }) ?? true,
              place.coordinate.latitude.isFinite, place.coordinate.longitude.isFinite else {
            throw SessionRecoveryFailure.invalidSnapshot
        }
        switch place.id {
        case .mapKit(let id):
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  id.utf8.count <= FavoritePlacesLimits.identityBytes,
                  !id.contains("\0") else { throw SessionRecoveryFailure.invalidSnapshot }
        case .coordinate(let coordinate):
            guard coordinate == place.coordinate else { throw SessionRecoveryFailure.invalidSnapshot }
        }
    }

    private static func validate(_ coordinate: GeoCoordinate) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { throw SessionRecoveryFailure.invalidSnapshot }
    }

    private static func validate(_ progress: RouteProgress, route: PlannedRoute) throws {
        guard progress.committedDistanceMeters.isFinite,
              progress.totalDistanceMeters.isFinite,
              progress.totalDistanceMeters > 0,
              progress.committedDistanceMeters >= 0,
              progress.committedDistanceMeters <= progress.totalDistanceMeters,
              progress.totalDistanceMeters == route.totalDistanceMeters,
              valid(progress.activeElapsed), valid(progress.estimatedRemaining) else {
            throw SessionRecoveryFailure.invalidSnapshot
        }
    }

    private static func valid(_ duration: Duration) -> Bool {
        let components = duration.components
        return components.seconds >= 0 && components.seconds <= SessionRecoveryLimits.durationSeconds &&
            components.attoseconds >= 0 && components.attoseconds < 1_000_000_000_000_000_000
    }

    private struct Version: Decodable { let schemaVersion: Int }

    private struct Archive: Codable {
        let schemaVersion: Int
        let revision: UInt64
        let mode: SessionMapMode
        let draft: DraftDTO
        let roundTripEnabled: Bool
        let joystickSpeed: Int
        let position: PositionDTO?

        init(snapshot: SessionRecoverySnapshot, revision: UInt64, encodeGPX: (GPXDocument) throws -> Data) throws {
            schemaVersion = SessionRecoveryLimits.schemaVersion
            self.revision = revision
            mode = snapshot.mode
            draft = try DraftDTO(snapshot.draft, encodeGPX: encodeGPX)
            roundTripEnabled = snapshot.roundTripEnabled
            joystickSpeed = snapshot.joystickSpeed.kilometersPerHour
            position = snapshot.position.map(PositionDTO.init)
        }

        func snapshot() throws -> (snapshot: SessionRecoverySnapshot, revision: UInt64) {
            guard let speed = RouteSpeed(kilometersPerHour: joystickSpeed) else { throw SessionRecoveryFailure.invalidSnapshot }
            let rootDraft = try draft.value()
            return (SessionRecoverySnapshot(mode: mode, draft: rootDraft,
                roundTripEnabled: roundTripEnabled, joystickSpeed: speed,
                position: try position?.value()), revision)
        }
    }

    private struct CoordinateDTO: Codable {
        let latitude: Double
        let longitude: Double
        init(_ value: GeoCoordinate) { latitude = value.latitude; longitude = value.longitude }
        func value() throws -> GeoCoordinate {
            guard let value = GeoCoordinate(latitude: latitude, longitude: longitude) else { throw SessionRecoveryFailure.invalidSnapshot }
            return value
        }
    }

    private struct IdentityDTO: Codable {
        let kind: String
        let value: String?
        init(_ identity: PlaceIdentity) {
            switch identity {
            case .mapKit(let value): kind = "mapKit"; self.value = value
            case .coordinate: kind = "coordinate"; value = nil
            }
        }
        func value(coordinate: GeoCoordinate) throws -> PlaceIdentity {
            switch kind {
            case "mapKit":
                guard let value, !value.isEmpty else { throw SessionRecoveryFailure.invalidSnapshot }
                return .mapKit(value)
            case "coordinate":
                guard value == nil else { throw SessionRecoveryFailure.invalidSnapshot }
                return .coordinate(coordinate)
            default: throw SessionRecoveryFailure.invalidSnapshot
            }
        }
    }

    private struct PlaceDTO: Codable {
        let identity: IdentityDTO
        let coordinate: CoordinateDTO
        let title: String
        let address: String?
        init(_ value: MapPlace) {
            identity = IdentityDTO(value.id); coordinate = CoordinateDTO(value.coordinate)
            title = value.title; address = value.address
        }
        func value() throws -> MapPlace {
            let coordinate = try self.coordinate.value()
            let identity = try self.identity.value(coordinate: coordinate)
            let place = MapPlace(id: identity, title: title, coordinate: coordinate, address: address)
            guard place.title == title, place.address == address else { throw SessionRecoveryFailure.invalidSnapshot }
            try validate(place)
            return place
        }
    }

    private struct NodeDTO: Codable {
        let id: UUID
        let kind: String
        let place: PlaceDTO?
        init(_ node: RouteNode) {
            id = node.id.rawValue
            switch node.value {
            case .current: kind = "current"; place = nil
            case .empty: kind = "empty"; place = nil
            case .place(let value): kind = "place"; place = PlaceDTO(value)
            }
        }
        func value() throws -> RouteNode {
            switch kind {
            case "current": guard place == nil else { throw SessionRecoveryFailure.invalidSnapshot }; return RouteNode(id: RouteNodeID(rawValue: id), value: .current)
            case "empty": guard place == nil else { throw SessionRecoveryFailure.invalidSnapshot }; return RouteNode(id: RouteNodeID(rawValue: id), value: .empty)
            case "place": guard let place else { throw SessionRecoveryFailure.invalidSnapshot }; return RouteNode(id: RouteNodeID(rawValue: id), value: .place(try place.value()))
            default: throw SessionRecoveryFailure.invalidSnapshot
            }
        }
    }

    private struct DraftDTO: Codable {
        let sourceKind: String
        let speed: Int
        let nodes: [NodeDTO]?
        let gpxData: Data?
        let gpxFilename: String?

        init(_ value: RouteDraft, encodeGPX: (GPXDocument) throws -> Data = { try GPXCodec.encode($0) }) throws {
            speed = value.speed.kilometersPerHour
            switch value.source {
            case .manual(let nodes):
                sourceKind = "manual"; self.nodes = nodes.map(NodeDTO.init); gpxData = nil; gpxFilename = nil
            case .gpx(let source):
                sourceKind = "gpx"; nodes = nil; gpxData = try encodeGPX(source.document); gpxFilename = source.displayFilename
            }
        }

        func value() throws -> RouteDraft {
            guard let speed = RouteSpeed(kilometersPerHour: speed) else { throw SessionRecoveryFailure.invalidSnapshot }
            switch sourceKind {
            case "manual":
                guard gpxData == nil, gpxFilename == nil, let nodes else { throw SessionRecoveryFailure.invalidSnapshot }
                // Snapshots saved before empty endpoints existed hold a lone start node.
                var decoded = try nodes.map { try $0.value() }
                while decoded.count < 2 { decoded.append(RouteNode(value: .empty)) }
                guard let draft = RouteDraft(nodes: decoded, speed: speed) else {
                    throw SessionRecoveryFailure.invalidSnapshot
                }
                return draft
            case "gpx":
                guard nodes == nil, let gpxData, gpxData.count <= SessionRecoveryLimits.inputGPXBytes,
                      let gpxFilename else { throw SessionRecoveryFailure.invalidSnapshot }
                let document: GPXDocument
                do { document = try GPXCodec.decode(gpxData) }
                catch { throw SessionRecoveryFailure.invalidSnapshot }
                guard let source = try? GPXRouteSource(document: document, displayFilename: gpxFilename) else {
                    throw SessionRecoveryFailure.invalidSnapshot
                }
                return RouteDraft(gpx: source, speed: speed)
            default: throw SessionRecoveryFailure.invalidSnapshot
            }
        }
    }

    private struct PositionDTO: Codable {
        let coordinate: CoordinateDTO
        let source: String
        init(_ value: SessionDisplayPosition) { coordinate = CoordinateDTO(value.coordinate); source = value.source == .gps ? "gps" : "simulation" }
        func value() throws -> SessionDisplayPosition {
            let source: PositionSource
            switch self.source { case "gps": source = .gps; case "simulation": source = .simulation; default: throw SessionRecoveryFailure.invalidSnapshot }
            return SessionDisplayPosition(coordinate: try coordinate.value(), source: source)
        }
    }

    private struct DurationDTO: Codable {
        let seconds: Int64
        let attoseconds: Int64
        init(_ value: Duration) { let c = value.components; seconds = c.seconds; attoseconds = c.attoseconds }
        func value() throws -> Duration {
            guard seconds >= 0, seconds <= SessionRecoveryLimits.durationSeconds,
                  attoseconds >= 0, attoseconds < 1_000_000_000_000_000_000 else { throw SessionRecoveryFailure.invalidSnapshot }
            return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
        }
    }

    private struct ProgressDTO: Codable {
        let committed: Double
        let total: Double
        let activeElapsed: DurationDTO
        let estimatedRemaining: DurationDTO
        init(_ value: RouteProgress) {
            committed = value.committedDistanceMeters; total = value.totalDistanceMeters
            activeElapsed = DurationDTO(value.activeElapsed); estimatedRemaining = DurationDTO(value.estimatedRemaining)
        }
        func value(route: PlannedRoute) throws -> RouteProgress {
            let value = RouteProgress(committedDistanceMeters: committed, totalDistanceMeters: total,
                                      activeElapsed: try activeElapsed.value(), estimatedRemaining: try estimatedRemaining.value())
            try validate(value, route: route)
            return value
        }
    }

    private struct RouteDTO: Codable {
        let draft: DraftDTO?
        let points: [CoordinateDTO]
        let progress: ProgressDTO
        let roundTripEnabled: Bool
        let usesPositionAxis: Bool
        let heading: String
        let state: SessionSavedTaskState
        init(_ value: SessionRouteRecovery, rootDraft: RouteDraft) throws {
            draft = value.draft == rootDraft ? nil : try DraftDTO(value.draft)
            points = value.route.points.map(CoordinateDTO.init); progress = ProgressDTO(value.progress)
            roundTripEnabled = value.roundTripEnabled; usesPositionAxis = value.usesPositionAxis
            heading = value.heading.rawValue; state = value.state
        }
        func value(fallbackDraft: RouteDraft) throws -> SessionRouteRecovery {
            let draft = try self.draft?.value() ?? fallbackDraft
            guard let heading = RouteHeading(rawValue: self.heading) else { throw SessionRecoveryFailure.invalidSnapshot }
            let points = try self.points.map { try $0.value() }
            guard points.count >= 2, points.count <= SessionRecoveryLimits.activePathPoints,
                  let first = points.first, let last = points.last else { throw SessionRecoveryFailure.invalidSnapshot }
            let route: PlannedRoute
            do { route = try PlannedRoute(points: points, from: first, to: last) }
            catch { throw SessionRecoveryFailure.invalidSnapshot }
            guard route.points == points else { throw SessionRecoveryFailure.invalidSnapshot }
            return SessionRouteRecovery(draft: draft, route: route,
                progress: try progress.value(route: route), roundTripEnabled: roundTripEnabled,
                usesPositionAxis: usesPositionAxis, heading: heading, state: state)
        }
    }

    private struct WanderDTO: Codable {
        let targetID: UUID
        let target: PlaceDTO
        let speed: Int
        let history: [CoordinateDTO]
        let lastAcknowledgedCoordinate: CoordinateDTO
        let lastAcknowledgedBearingDegrees: Double?
        let state: SessionSavedTaskState
        init(_ value: SessionWanderRecovery) {
            targetID = value.target.id; target = PlaceDTO(value.target.place); speed = value.speed.kilometersPerHour
            history = value.history.map(CoordinateDTO.init)
            lastAcknowledgedCoordinate = CoordinateDTO(value.lastAcknowledgedCoordinate)
            lastAcknowledgedBearingDegrees = value.lastAcknowledgedBearingDegrees; state = value.state
        }
        func value() throws -> SessionWanderRecovery {
            guard let speed = RouteSpeed(kilometersPerHour: speed), history.count <= SessionRecoveryLimits.historyPoints else {
                throw SessionRecoveryFailure.invalidSnapshot
            }
            let target = WanderTarget(id: targetID, place: try target.value())
            let bearing = lastAcknowledgedBearingDegrees
            if let bearing { guard bearing.isFinite, (0..<360).contains(bearing) else { throw SessionRecoveryFailure.invalidSnapshot } }
            return SessionWanderRecovery(target: target, speed: speed,
                history: try history.map { try $0.value() },
                lastAcknowledgedCoordinate: try lastAcknowledgedCoordinate.value(),
                lastAcknowledgedBearingDegrees: bearing, state: state)
        }
    }

    private struct ActiveDTO: Codable {
        let kind: String
        let route: RouteDTO?
        let wander: WanderDTO?
        init(_ value: SessionActiveRecovery, rootDraft: RouteDraft) throws {
            switch value {
            case .route(let value): kind = "route"; route = try RouteDTO(value, rootDraft: rootDraft); wander = nil
            case .wander(let value): kind = "wander"; route = nil; wander = WanderDTO(value)
            case .manual: kind = "manual"; route = nil; wander = nil
            }
        }
        func value(fallbackDraft: RouteDraft) throws -> SessionActiveRecovery {
            switch kind {
            case "route": guard let route, wander == nil else { throw SessionRecoveryFailure.invalidSnapshot }; return .route(try route.value(fallbackDraft: fallbackDraft))
            case "wander": guard let wander, route == nil else { throw SessionRecoveryFailure.invalidSnapshot }; return .wander(try wander.value())
            case "manual": guard route == nil, wander == nil else { throw SessionRecoveryFailure.invalidSnapshot }; return .manual
            default: throw SessionRecoveryFailure.invalidSnapshot
            }
        }
    }

    private struct UncertaintyDTO: Codable {
        let source: SessionUncertaintySource
        let requestedPlace: PlaceDTO?
        init(_ value: SessionMovementUncertainty) throws { source = value.source; requestedPlace = value.requestedPlace.map(PlaceDTO.init) }
        func value() throws -> SessionMovementUncertainty {
            SessionMovementUncertainty(source: source, requestedPlace: try requestedPlace?.value())
        }
    }
}
