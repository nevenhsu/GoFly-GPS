import Foundation
import Darwin

public struct MacBundleResources: Sendable {
    public let resourcesURL: URL
    public let pythonURL: URL
    public let bridgeURL: URL
    public let projectURL: URL
    public let stateRootURL: URL
    public let developerDirectoryURL: URL

    public init(
        resourcesURL: URL,
        developerDirectoryURL: URL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer")
    ) throws {
        guard resourcesURL.isFileURL else { throw CheckFailure.bundleInvalid }
        let root = resourcesURL.standardizedFileURL
        let python = root.appendingPathComponent("Python/python/install/bin/python3.14")
        let bridge = root.appendingPathComponent("Bridge/bridge.py")
        // Only the empty signing stub ships; GoFly itself is the saved, verified IPA.
        let project = root.appendingPathComponent("SigningStub/GoFly.xcodeproj")
        let projectFile = project.appendingPathComponent("project.pbxproj")
        let stubSource = root.appendingPathComponent("SigningStub/main.c")
        let ipaStore = root.appendingPathComponent("Bridge/Setup/ipa_store.py")
        let ipaResign = root.appendingPathComponent("Bridge/Setup/ipa_resign.py")
        let wire = root.appendingPathComponent("Bridge/wire.py")
        let deviceBoundary = root.appendingPathComponent("Bridge/Device/gofly_device.py")
        let setupProtocol = root.appendingPathComponent("Bridge/Setup/setup_protocol.py")
        let setupConfig = root.appendingPathComponent("Bridge/Setup/setup_config.py")
        let setupJournal = root.appendingPathComponent("Bridge/Setup/setup_journal.py")
        let setupProducer = root.appendingPathComponent("Bridge/Setup/setup_producer.py")
        let setupAdapters = root.appendingPathComponent("Bridge/Setup/setup_adapters.py")
        let setupSupport = root.appendingPathComponent("Bridge/Setup/setup_support.py")
        let sitePackages = root.appendingPathComponent("Python/python/install/lib/python3.14/site-packages", isDirectory: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let requiredFiles = [bridge, projectFile, stubSource, wire, deviceBoundary,
                             setupProtocol, setupConfig, setupJournal, setupProducer,
                             setupAdapters, setupSupport, ipaStore, ipaResign]
        guard root.path.hasPrefix("/"), !Self.isSymlink(root),
              requiredFiles.allSatisfy(Self.isRegularFile),
              Self.isDirectory(project), Self.isDirectory(sitePackages),
              FileManager.default.isExecutableFile(atPath: python.path) else {
            throw CheckFailure.bundleInvalid
        }
        self.resourcesURL = root
        self.pythonURL = python
        self.bridgeURL = bridge
        self.projectURL = project
        self.stateRootURL = support.appendingPathComponent("GoFly/state", isDirectory: true)
        self.developerDirectoryURL = developerDirectoryURL.standardizedFileURL
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

/// One bounded Python process boundary for read-only checks and setup.
public struct ProcessBridge: MacChecking, MacSetupRunning {
    private let bundle: MacBundleResources

    public init(bundle: MacBundleResources) {
        self.bundle = bundle
    }

    private var arguments: [String] {
        [
            "-I", "-B", bundle.bridgeURL.path,
            "--resources", bundle.resourcesURL.path,
            "--developer-directory", bundle.developerDirectoryURL.path,
            "--target-name", "GoFly",
        ]
    }

    public func check(_ request: CheckRequest) async throws -> Data {
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw CheckFailure.invalidResponse }
        let runner = BoundedProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached {
                try runner.run(executable: self.bundle.pythonURL.path,
                               arguments: self.arguments,
                               developerDirectory: self.bundle.developerDirectoryURL.path, input: input,
                               timeout: request.action == .ipaImport ? 1_800
                                   : request.action == .ipaRelease ? 90
                                   : request.action == .inspect ? 100 : 45)
            }.value
        } onCancel: { runner.cancel(reason: .cancelled) }
    }

    public func run(_ request: MacSetupRequest) async throws -> Data {
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw MacSetupFailure.invalidRequest }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(executable: self.bundle.pythonURL.path,
                                    arguments: self.arguments,
                                    developerDirectory: self.bundle.developerDirectoryURL.path, input: input,
                                    timeout: request.action == .status ? 30 : request.action == .preflight ? 120 : 1_800)
                }.value
            } onCancel: { process.cancel(reason: .cancelled) }
        } catch let error as CheckFailure {
            switch error {
            case .cancelled: throw MacSetupFailure.cancelled
            case .timeout: throw MacSetupFailure.timeout
            case .unavailable: throw MacSetupFailure.unavailable
            default: throw MacSetupFailure.invalidResponse
            }
        } catch is CancellationError { throw MacSetupFailure.cancelled }
    }
}

public struct BridgeStatusJournalReader: MacSetupJournalReading {
    private let runner: any MacSetupRunning

    public init(runner: any MacSetupRunning) { self.runner = runner }

    public func readPendingTransaction() async throws -> MacSetupTransactionIdentity? {
        try await readState().pendingTransaction
    }

    public func readState() async throws -> MacSetupJournalState {
        let request = try MacSetupRequest(action: .status)
        do {
            let data = try await runner.run(request)
            let root = try SetupWireJSON.object(data)
            if root["status"] as? String == "error" {
                guard root["action"] as? String == "status",
                      let rawID = root["requestID"] as? String,
                      UUID(uuidString: rawID) == request.requestID,
                      root["code"] as? String == "transaction-unknown" else {
                    throw MacSetupFailure.invalidResponse
                }
                return MacSetupJournalState(pendingTransaction: nil, completed: nil)
            }
            guard root["status"] as? String == "ok",
                  let rawID = root["setupID"] as? String, let id = UUID(uuidString: rawID),
                  let device = root["deviceID"] as? String else {
                throw MacSetupFailure.invalidResponse
            }
            let mode: MacSetupMode
            if let rawMode = root["mode"] as? String {
                guard let parsed = MacSetupMode(rawValue: rawMode) else {
                    throw MacSetupFailure.invalidResponse
                }
                mode = parsed
            } else {
                // Older journals predate the mode header.  They are installs.
                mode = .install
            }
            guard let transport = ConnectedDevice.Transport(rawValue: root["transport"] as? String ?? "usb") else {
                throw MacSetupFailure.invalidResponse
            }
            if let payload = root["payload"] as? [String: Any],
               payload["stage"] as? String == "complete",
               payload["outcome"] as? String == "confirmed" {
                // A completed journal has nothing pending and must never lock
                // the app.  Keep its snapshot for device-page facts only.
                guard let teamID = payload["teamID"] as? String else { throw MacSetupFailure.invalidResponse }
                let statusRequest = try MacSetupRequest(action: .status, requestID: request.requestID,
                                                        setupID: id, deviceID: device, mode: mode,
                                                        transport: transport, teamID: teamID)
                let completed = try? MacSetupResponseDecoder.decode(data, for: statusRequest)
                return MacSetupJournalState(pendingTransaction: nil, completed: completed)
            }
            let (identity, snapshot) = try MacSetupResponseDecoder.probe(data)
            guard identity.setupID == id, identity.deviceID == device, identity.mode == mode else {
                throw MacSetupFailure.invalidResponse
            }
            return MacSetupJournalState(pendingTransaction: identity, pendingSnapshot: snapshot, completed: nil)
        } catch MacSetupFailure.service("transaction-unknown") {
            return MacSetupJournalState(pendingTransaction: nil, completed: nil)
        } catch let error as MacSetupFailure {
            throw error
        } catch {
            throw MacSetupFailure.invalidResponse
        }
    }
}

public struct UnavailableChecker: MacChecking, MacSetupRunning {
    public let reason: CheckFailure
    public init(reason: CheckFailure = .unavailable) { self.reason = reason }
    public func check(_ request: CheckRequest) async throws -> Data { throw reason }
    public func run(_ request: MacSetupRequest) async throws -> Data { throw MacSetupFailure.unavailable }
}

/// Owns one child. No shell, no logs, bounded output, and group termination on cancellation.
public final class BoundedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var failure: CheckFailure?
    private var finished = false

    public init() {}

    public func cancel(reason: CheckFailure) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if failure == nil { failure = reason }
        let child = process
        lock.unlock()
        guard let child else { return }
        let pid = child.processIdentifier
        kill(-pid, SIGTERM)
        if child.isRunning { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.lock.lock()
            let active = !self.finished
            self.lock.unlock()
            if active { kill(-pid, SIGKILL); if child.isRunning { kill(pid, SIGKILL) } }
        }
    }

    public func run(executable: String, arguments: [String], developerDirectory: String, input: Data,
                    timeout: TimeInterval) throws -> Data {
        let child = Process()
        let output = Pipe()
        let stdin = Pipe()
        let diagnostics = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                             "DEVELOPER_DIR": developerDirectory, "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = stdin
        child.standardOutput = output
        child.standardError = diagnostics
        lock.lock()
        if let failure { lock.unlock(); throw failure }
        guard !finished, process == nil else { lock.unlock(); throw CheckFailure.unavailable }
        process = child
        do { try child.run() } catch { finished = true; lock.unlock(); throw CheckFailure.unavailable }
        lock.unlock()
        let deadline = DispatchWorkItem { self.cancel(reason: .timeout) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            lock.lock(); finished = true; process = nil; lock.unlock()
            try? output.fileHandleForReading.close()
            try? stdin.fileHandleForWriting.close()
            try? diagnostics.fileHandleForReading.close()
        }
        let streams = DispatchGroup()
        streams.enter()
        DispatchQueue.global().async {
            defer { streams.leave() }
            var size = 0
            while true {
                let chunk = diagnostics.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                guard size <= 65_536 - chunk.count else { self.cancel(reason: .invalidResponse); break }
                size += chunk.count
            }
        }
        streams.enter()
        DispatchQueue.global().async {
            defer { streams.leave() }
            do {
                try stdin.fileHandleForWriting.write(contentsOf: input)
                try stdin.fileHandleForWriting.close()
            } catch { self.cancel(reason: .invalidResponse) }
        }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count + chunk.count <= 262_144 else { cancel(reason: .invalidResponse); break }
            data.append(chunk)
        }
        child.waitUntilExit()
        streams.wait()
        lock.lock(); let finalFailure = failure; lock.unlock()
        if let finalFailure { throw finalFailure }
        guard !data.isEmpty else { throw CheckFailure.invalidResponse }
        return data
    }
}
