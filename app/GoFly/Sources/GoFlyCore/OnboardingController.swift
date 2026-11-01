import Combine
import Foundation

public protocol TunnelProbing: Sendable {
    func check() async throws
    /// Platform detail behind the most recent failed check, for display only.
    var lastFailureDetail: String? { get }
}

extension TunnelProbing {
    public var lastFailureDetail: String? { nil }
}

public enum TunnelProbeFailure: Error, Equatable, Sendable {
    case unavailable
    case timedOut
    /// No remotepairingd service could be found on this device; usually the
    /// Local Network permission is off.
    case serviceNotFound
}

public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
public protocol LocationAuthorizing: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
}

public enum OnboardingStep: Equatable, Sendable {
    case welcome, location, vpn, complete
}

public enum VPNCheckState: Equatable, Sendable {
    case unknown, checking, reachable, unavailable, timedOut
}

@MainActor
public final class OnboardingController: ObservableObject {
    @Published public private(set) var step: OnboardingStep = .welcome
    @Published public private(set) var vpnState: VPNCheckState = .unknown
    /// iOS's own reason for the last failed check; nil unless `vpnState` is a failure.
    @Published public private(set) var vpnFailureDetail: String?
    /// Bumps on every failed check so a dismissed failure notice can appear again.
    @Published public private(set) var vpnFailureRevision: UInt64 = 0
    /// The last failed check found no pairing service, so the fix is the Local Network permission.
    @Published public private(set) var vpnNeedsLocalNetwork = false
    @Published public private(set) var isChecking = false
    @Published public private(set) var isAdvancing = false
    @Published public private(set) var isRequestingLocation = false
    @Published public private(set) var locationAuthorization: LocationAuthorization

    private let probe: any TunnelProbing
    private let location: any LocationAuthorizing
    private var navigationRevision: UInt64 = 0
    private var vpnActive = false
    private var generation: UInt64 = 0
    private var checkTask: Task<Void, Never>?
    private var pendingAdvance: (@MainActor () -> Void)?
    /// A user-requested check was cut short by leaving the foreground (e.g. the
    /// Local Network permission alert); it continues when the page is active again.
    private var resumeCheckWhenActive = false

    public init(probe: any TunnelProbing, location: any LocationAuthorizing) {
        self.probe = probe
        self.location = location
        self.locationAuthorization = location.authorization
    }

    deinit {
        checkTask?.cancel()
    }

    public var canAdvanceVPN: Bool { step == .vpn && vpnActive && vpnState == .reachable && !isAdvancing }
    public func advanceWelcome() {
        guard step == .welcome else { return }
        step = .location
    }
    public func skipLocation() {
        guard step == .location else { return }
        navigationRevision &+= 1
        isRequestingLocation = false
        step = .vpn
    }
    public func allowLocation() async {
        guard step == .location, !isRequestingLocation else { return }
        isRequestingLocation = true
        let token = navigationRevision
        let result = await location.requestAuthorization()
        guard step == .location, token == navigationRevision else { return }
        locationAuthorization = result
        skipLocation()
    }
    /// Settings may change permission while the location page is visible.
    public func refreshLocationAuthorization() {
        guard step == .location, !isRequestingLocation else { return }
        locationAuthorization = location.authorization
    }
    public func goBack() {
        switch step {
        case .location:
            navigationRevision &+= 1
            isRequestingLocation = false
            step = .welcome
        case .vpn:
            setVPNActive(false)
            navigationRevision &+= 1
            locationAuthorization = location.authorization
            step = .location
        case .welcome, .complete:
            break
        }
    }
    /// Marks the VPN page as visible and foregrounded. Never starts a check: probing
    /// happens only when the user asks via `checkConnection` / `advanceVPN`.
    public func setVPNActive(_ active: Bool) {
        guard active != vpnActive else { return }
        vpnActive = active
        generation &+= 1
        if active {
            drainPendingCheck()
        } else {
            resumeCheckWhenActive = checkTask != nil
            checkTask?.cancel()
            pendingAdvance = nil
            isAdvancing = false
            vpnState = .unknown
            vpnFailureDetail = nil
            vpnNeedsLocalNetwork = false
        }
    }
    public func checkConnection() {
        guard step == .vpn, vpnActive, checkTask == nil else { return }
        beginCheck(onAdvance: nil)
    }

    private func beginCheck(onAdvance: (@MainActor () -> Void)?) {
        let token = generation
        isChecking = true
        if vpnState == .unknown { vpnState = .checking }
        let probe = probe
        checkTask = Task { [weak self] in
            let result: Result<Void, any Error>
            do { try await probe.check(); result = .success(()) }
            catch { result = .failure(error) }
            guard let self else { return }
            self.checkTask = nil
            self.isChecking = false
            guard self.generation == token, self.vpnActive, self.step == .vpn else {
                self.drainPendingCheck()
                return
            }
            self.vpnNeedsLocalNetwork = false
            switch result {
            case .success, .failure(is CancellationError): self.vpnFailureDetail = nil
            case .failure: self.vpnFailureDetail = probe.lastFailureDetail
            }
            switch result {
            case .success:
                self.vpnState = .reachable
                if let onAdvance {
                    self.isAdvancing = false
                    self.setVPNActive(false)
                    self.step = .complete
                    onAdvance()
                    return
                }
            case .failure(is CancellationError): self.vpnState = .unknown
            case .failure(TunnelProbeFailure.serviceNotFound):
                self.vpnState = .unavailable
                self.vpnNeedsLocalNetwork = true
                self.vpnFailureRevision &+= 1
            case .failure(TunnelProbeFailure.timedOut):
                self.vpnState = .timedOut
                self.vpnFailureRevision &+= 1
            case .failure:
                self.vpnState = .unavailable
                self.vpnFailureRevision &+= 1
            }
            if onAdvance != nil { self.isAdvancing = false }
            self.drainPendingCheck()
        }
    }
    private func drainPendingCheck() {
        guard vpnActive, step == .vpn, checkTask == nil else { return }
        if let next = pendingAdvance {
            pendingAdvance = nil
            beginCheck(onAdvance: next)
        } else if resumeCheckWhenActive {
            resumeCheckWhenActive = false
            beginCheck(onAdvance: nil)
        }
    }
    public func advanceVPN(onAdvance: @escaping @MainActor () -> Void) {
        guard canAdvanceVPN else { return }
        isAdvancing = true
        if checkTask == nil { beginCheck(onAdvance: onAdvance) }
        else { pendingAdvance = onAdvance }
    }
}
