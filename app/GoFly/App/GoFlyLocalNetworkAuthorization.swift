import Combine
import Foundation
import GoFlyCore
import Network
import UIKit

/// Learns the Local Network permission by browsing the declared Bonjour
/// service. iOS has no query API: the first browse raises the system prompt,
/// a granted browse reaches `.ready`, and a denied one waits with a
/// policy-denied DNS error. The last answer is remembered so the settings
/// pages can show it without prompting.
@MainActor
final class GoFlyLocalNetworkAuthorization: ObservableObject, LocalNetworkAuthorizing {
    static let shared = GoFlyLocalNetworkAuthorization()

    private static let defaultsKey = "gofly.localNetwork.authorization"
    private nonisolated static let policyDenied: Int32 = -65570  // kDNSServiceErr_PolicyDenied

    @Published private(set) var authorization: LocalNetworkAuthorization
    private var inFlight: Task<LocalNetworkAuthorization, Never>?
    private var recoverySubscription: AnyCancellable?
    private var activeSubscription: AnyCancellable?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        authorization = switch stored {
        case "granted": .granted
        case "denied": .denied
        default: .unknown
        }
        // The answer can change in Settings while GoFly is in the background.
        activeSubscription = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    /// Records a failure the VPN probe attributed to the permission being off.
    func markDenied() { store(.denied) }
    /// A reachable tunnel proves the device service was found on the local network.
    func markGranted() { store(.granted) }

    /// Keeps the remembered answer in step with every tunnel probe, so each
    /// connection check names the same cause.
    func observe(_ recovery: ConnectionRecoveryController) {
        recoverySubscription = recovery.$needsLocalNetwork
            .combineLatest(recovery.$connectionState)
            .sink { [weak self] needsLocalNetwork, state in
                MainActor.assumeIsolated {
                    if needsLocalNetwork { self?.markDenied() }
                    else if state == .reachable { self?.markGranted() }
                }
            }
    }

    func requestAuthorization() async -> LocalNetworkAuthorization {
        if let inFlight { return await inFlight.value }
        let task = Task { await Self.browse() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        store(result)
        return result
    }

    /// Re-reads an already answered permission; an unanswered one stays unknown
    /// so merely opening a settings page never raises the prompt.
    func refresh() {
        guard authorization != .unknown else { return }
        Task { _ = await requestAuthorization() }
    }

    private func store(_ value: LocalNetworkAuthorization) {
        guard value != .unknown else { return }
        authorization = value
        UserDefaults.standard.set(value == .granted ? "granted" : "denied", forKey: Self.defaultsKey)
    }

    private nonisolated static func browse() async -> LocalNetworkAuthorization {
#if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-gofly-ui-local-network-denied") ? .denied : .granted
#else
        let browser = NWBrowser(for: .bonjour(type: "_remotepairing._tcp", domain: nil), using: NWParameters())
        let queue = DispatchQueue(label: "com.neven.gofly.localnetwork", qos: .userInitiated)
        return await withCheckedContinuation { (continuation: CheckedContinuation<LocalNetworkAuthorization, Never>) in
            let resolver = BrowseResolver(browser: browser, continuation: continuation)
            let finish = resolver.finish
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.granted)
                case .waiting(let error):
                    if case .dns(let code) = error, code == policyDenied { finish(.denied) }
                case .failed:
                    finish(.denied)
                default:
                    break
                }
            }
            browser.start(queue: queue)
            // The prompt may stay up for a long time; give up only well after that.
            queue.asyncAfter(deadline: .now() + 120) { finish(.unknown) }
        }
#endif
    }
}

/// Resumes a browse continuation exactly once. Every call arrives on the
/// browser's one serial queue, so `finished` needs no lock.
private final class BrowseResolver: @unchecked Sendable {
    private let browser: NWBrowser
    private let continuation: CheckedContinuation<LocalNetworkAuthorization, Never>
    private var finished = false

    init(browser: NWBrowser, continuation: CheckedContinuation<LocalNetworkAuthorization, Never>) {
        self.browser = browser
        self.continuation = continuation
    }

    func finish(_ result: LocalNetworkAuthorization) {
        guard !finished else { return }
        finished = true
        browser.cancel()
        continuation.resume(returning: result)
    }
}
