import Foundation

/// The joystick origin request the map screen makes: whether it is setting an
/// origin, and the teleport intent sent for it once one is.
public struct JoystickOriginRequest: Equatable, Sendable {
    public var isSetting: Bool
    public var intentID: UUID?
    public init(isSetting: Bool = false, intentID: UUID? = nil) {
        self.isSetting = isSetting; self.intentID = intentID
    }
    /// Setting an origin and still waiting for a location fix to send.
    var awaitsFix: Bool { isSetting && intentID == nil }
}

/// Screen state the origin flow reads. The map screen attaches one on appear;
/// until then the flow sees an inactive scene outside joystick mode.
@MainActor
public struct JoystickOriginHost {
    public var isJoystickMode: @MainActor () -> Bool
    public var isSceneActive: @MainActor () -> Bool
    /// Ask for one fresh real location fix.
    public var requestLocationFix: @MainActor () -> Void
    /// The visible map's origin point (one third down the screen, clear of the panel), when known.
    public var mapCenter: @MainActor () -> GeoCoordinate?

    public init(isJoystickMode: @escaping @MainActor () -> Bool,
                isSceneActive: @escaping @MainActor () -> Bool,
                requestLocationFix: @escaping @MainActor () -> Void,
                mapCenter: @escaping @MainActor () -> GeoCoordinate? = { nil }) {
        self.isJoystickMode = isJoystickMode; self.isSceneActive = isSceneActive
        self.requestLocationFix = requestLocationFix
        self.mapCenter = mapCenter
    }

    static let detached = JoystickOriginHost(isJoystickMode: { false }, isSceneActive: { false },
                                             requestLocationFix: {})
}

/// Establishes the joystick origin by teleporting to fresh GPS or a currently
/// validated simulation marker. Warmup and retained display history are never
/// accepted as position acknowledgement, and an existing origin is never replaced.
@MainActor
public final class JoystickOriginController: ObservableObject {
    @Published public internal(set) var request = JoystickOriginRequest()

    private let service: ServiceController
    private let joystick: JoystickMovementController
    private var host = JoystickOriginHost.detached

    public init(service: ServiceController, joystick: JoystickMovementController) {
        self.service = service; self.joystick = joystick
    }

    public func attach(_ host: JoystickOriginHost) { self.host = host }

    /// The teleport intent is the automatic joystick origin, which never moves the camera.
    public func isOrigin(_ intentID: UUID) -> Bool { request.isSetting && request.intentID == intentID }

    /// The person touched the joystick with no origin: take the visible map's upper-third
    /// point as the origin and start simulating there.
    public func establishFromMap() {
        guard host.isJoystickMode(), !request.isSetting, joystick.requiresOrigin,
              service.canTeleport, let center = host.mapCenter() else { return }
        request.isSetting = true
        submit(center)
    }

    public func cancel() { request = JoystickOriginRequest() }

    public func ensure() {
        // Only when there is no origin yet; an existing one is never replaced.
        guard host.isJoystickMode(), !request.isSetting, joystick.requiresOrigin else { return }
        if let marker = service.displayPositionMarker,
           marker.source == .simulation, marker.freshness == .fresh { return }
        request.isSetting = true
        if let marker = service.displayPositionMarker,
           marker.source == .gps, marker.freshness == .fresh {
            submit(marker.coordinate)
        } else if let marker = service.displayPositionMarker, marker.source == .simulation {
            // The last simulated position (restored after a cold launch).
            submit(marker.coordinate)
        } else {
            host.requestLocationFix()
        }
    }

    private func submit(_ coordinate: GeoCoordinate) {
        guard host.isJoystickMode(), request.awaitsFix else { return }
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        guard service.teleport(to: TeleportCandidate(place: place)),
              case .preparing(let intent) = service.pointState else {
            request.isSetting = false
            return
        }
        request.intentID = intent.id
    }

    /// A launch-time origin can be refused while the scene fence or tunnel is
    /// still closed; retry once admission opens instead of leaving the joystick
    /// disabled until the person taps Start.
    public func receive(_ event: JoystickCommandEvent) {
        guard case .availabilityChanged = event, host.isJoystickMode(), !request.isSetting,
              host.isSceneActive(), joystick.requiresOrigin, service.canTeleport else { return }
        ensure()
    }

    // MARK: Location fixes

    /// The location source stopped without a fix.
    public func fixUnavailable() {
        if request.awaitsFix, host.isJoystickMode() { request.isSetting = false }
    }

    /// The service accepted a real fix; `coordinate` is nil when it is not a valid coordinate.
    public func fixAccepted(_ coordinate: GeoCoordinate?) {
        guard request.awaitsFix, host.isJoystickMode() else { return }
        guard let coordinate else { request.isSetting = false; return }
        submit(coordinate)
    }

    // MARK: Teleports

    /// A Go teleport. In joystick mode it replaces an origin still waiting for a
    /// fix; elsewhere it becomes the origin a pending request waits for.
    public func go(to candidate: TeleportCandidate) {
        if host.isJoystickMode() {
            let wasEstablishingOrigin = request.awaitsFix
            request.isSetting = false
            if service.teleport(to: candidate), wasEstablishingOrigin,
               case .preparing(let intent) = service.pointState {
                request.intentID = intent.id
            }
        } else if service.teleport(to: candidate), request.isSetting,
                  case .preparing(let intent) = service.pointState {
            request.intentID = intent.id
        }
    }

    /// The teleport `intentID` settled. Returns true when it was this origin,
    /// which is then no longer being set.
    @discardableResult public func settle(_ intentID: UUID) -> Bool {
        guard isOrigin(intentID) else { return false }
        request = JoystickOriginRequest()
        return true
    }
}
