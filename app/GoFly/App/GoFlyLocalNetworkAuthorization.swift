import Combine
import Foundation
import GoFlyCore
import Network
import UIKit

/// Learns the Local Network permission by browsing the declared Bonjour
/// service. iOS has no query API: the first browse raises the system prompt,
/// a granted browse finds GoFly's own advertised probe service, and a denied one waits with a
/// policy-denied DNS error. The last answer is remembered so the settings
/// pages can show it without prompting.
@MainActor
final class GoFlyLocalNetworkAuthorization: ObservableObject, LocalNetworkAuthorizing {
    static let shared = GoFlyLocalNetworkAuthorization()

    private static let defaultsKey = "gofly.localNetwork.authorization"
    private nonisolated static let probeService = "_gofly-probe._tcp"
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

    /// A reachable tunnel proves the device service was found on the local network.
    func markGranted() { store(.granted) }

    /// A reachable tunnel proves the permission. A probe that cannot find the device
    /// service is not evidence it is off (LocalDevVPN may simply not be connected), so
    /// denial comes only from the system's own answer in `requestAuthorization`.
    func observe(_ recovery: ConnectionRecoveryController) {
        recoverySubscription = recovery.$connectionState
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    if state == .reachable { self?.markGranted() }
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
        // `.ready` fires before the user answers the system prompt, so it proves
        // nothing. GoFly advertises a private service of its own and browses for
        // it: the browse only reports that result once Local Network is allowed.
        let browser = NWBrowser(for: .bonjour(type: probeService, domain: nil), using: NWParameters())
        let listener = try? NWListener(using: .tcp)
        listener?.service = NWListener.Service(name: UUID().uuidString, type: probeService)
        listener?.newConnectionHandler = { $0.cancel() }
        let queue = DispatchQueue(label: "com.neven.gofly.localnetwork", qos: .userInitiated)
        return await withCheckedContinuation { (continuation: CheckedContinuation<LocalNetworkAuthorization, Never>) in
            let resolver = BrowseResolver(browser: browser, listener: listener, continuation: continuation)
            let finish = resolver.finish
            let deniedIfPolicy: @Sendable (NWError) -> Void = { error in
                if case .dns(let code) = error, code == policyDenied { finish(.denied) }
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error): deniedIfPolicy(error)
                case .failed: finish(.denied)
                default: break
                }
            }
            listener?.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error): deniedIfPolicy(error)
                default: break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                if !results.isEmpty { finish(.granted) }
            }
            listener?.start(queue: queue)
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
    private let listener: NWListener?
    private let continuation: CheckedContinuation<LocalNetworkAuthorization, Never>
    private var finished = false

    init(browser: NWBrowser, listener: NWListener?,
         continuation: CheckedContinuation<LocalNetworkAuthorization, Never>) {
        self.browser = browser
        self.listener = listener
        self.continuation = continuation
    }

    func finish(_ result: LocalNetworkAuthorization) {
        guard !finished else { return }
        finished = true
        browser.cancel()
        listener?.cancel()
        continuation.resume(returning: result)
    }
}
