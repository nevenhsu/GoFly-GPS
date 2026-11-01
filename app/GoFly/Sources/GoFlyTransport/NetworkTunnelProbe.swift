import Foundation
import GoFlyCore

/// Every check owns a fresh TCP connection. A reachable tunnel never starts a
/// device service or performs authentication, pairing, mounting or location work.
public struct NetworkTunnelProbe: TunnelProbing {
    private let timeout: TimeInterval
    private let makeConnection: @Sendable () -> any TunnelConnection
    private let discoversPort: Bool
    private let diagnostics = ProbeDiagnostics()

    public init() {
        self.init(timeout: LocalTunnelEndpoint.timeoutSeconds, discoversPort: true, makeConnection: {
            // check() discovers the port first; port 0 never connects, so a miss reads as unavailable.
            NetworkConnection(host: LocalTunnelEndpoint.host, port: LocalTunnelEndpoint.port ?? 0)
        })
    }

    init(host: String, port: UInt16, timeout: TimeInterval) {
        self.init(timeout: timeout, makeConnection: { NetworkConnection(host: host, port: port) })
    }

    init(timeout: TimeInterval, discoversPort: Bool = false,
         makeConnection: @escaping @Sendable () -> any TunnelConnection) {
        precondition(timeout.isFinite && timeout >= 0)
        self.timeout = timeout
        self.discoversPort = discoversPort
        self.makeConnection = makeConnection
    }

    /// The last non-ready connection detail of the most recent failed check.
    public var lastFailureDetail: String? { diagnostics.value }

    public func check() async throws {
        // iOS assigns remotepairingd's port dynamically; look it up before each check.
        if discoversPort {
            let found = await RemotePairingPort.discover(timeout: timeout)
            try Task.checkCancellation()
            if found == nil, RemotePairingPort.current == nil {
                diagnostics.value = "no _remotepairing._tcp service found on this device"
                throw TunnelProbeFailure.serviceNotFound
            }
        }
        let operation = ProbeOperation(connection: makeConnection(), timeout: timeout, diagnostics: diagnostics)
        try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: {
            operation.cancel()
        }
    }

    #if DEBUG
    /// A real unreachable endpoint for bounded simulator UI verification.
    /// This does not expose a caller-selected endpoint or manufacture success.
    public static var unavailableUITestProbe: NetworkTunnelProbe {
        NetworkTunnelProbe(host: "127.0.0.1", port: 0, timeout: LocalTunnelEndpoint.timeoutSeconds)
    }
    #endif
}

private final class ProbeDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// All mutable state, including cancellation before continuation installation,
/// lives on this one queue. The first terminal result closes and resumes once.
private final class ProbeOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.neven.gofly.tunnel-probe")
    private let connection: any TunnelConnection
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private var timer: DispatchWorkItem?
    private let diagnostics: ProbeDiagnostics
    private var lastDetail: String?

    init(connection: any TunnelConnection, timeout: TimeInterval, diagnostics: ProbeDiagnostics) {
        self.connection = connection
        self.timeout = timeout
        self.diagnostics = diagnostics
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { self.install(continuation) }
        }
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func install(_ continuation: CheckedContinuation<Void, Error>) {
        if let result {
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        guard timeout > 0 else {
            finish(.failure(TunnelProbeFailure.timedOut))
            return
        }
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(TunnelProbeFailure.timedOut))
        }
        self.timer = timer
        queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        connection.start(on: queue) { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.finish(.success(()))
            case .unavailable(let detail):
                if let detail { self.lastDetail = detail }
                self.finish(.failure(TunnelProbeFailure.unavailable))
            case .pending(let detail): self.lastDetail = detail
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        switch result {
        case .success: diagnostics.value = nil
        case .failure(is CancellationError): break
        case .failure(TunnelProbeFailure.timedOut):
            diagnostics.value = "timed out after \(timeout)s; last state " + (lastDetail ?? "none reported")
        case .failure: diagnostics.value = lastDetail ?? "no detail reported"
        }
        timer?.cancel()
        timer = nil
        connection.cancel()
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
