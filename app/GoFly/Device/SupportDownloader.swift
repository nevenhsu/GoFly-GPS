import CryptoKit
import Foundation
import GoFlyCore

/// Downloads the device support files (DDI) for sideloaded installs that have
/// no Mac-provisioned support. The files land in `Documents/DDI` in the layout
/// `ProvisionedSupport` reads; mounting stays in `NativeDeviceSession`, which
/// has Apple personalize the image for this device on every mount, so one
/// download keeps working across iOS updates.
///
/// Source: the community DeveloperDiskImage mirror also used by the Mac setup's
/// bundled pymobiledevice3. Apple publishes no anonymous DDI download.
enum SupportDownloadFailure: String, Error, Equatable {
    case network = "support.download.error.network"
    case invalid = "support.download.error.invalid"
    case storage = "support.download.error.storage"
}

struct SupportDownloader: Sendable {
    enum Method: String, Sendable { case personalized, cryptex }

    /// Bytes received so far and the expected total once every size is known.
    typealias Progress = @Sendable (_ received: Int64, _ total: Int64?) -> Void

    private static let baseURL = URL(string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages/")!
    private static let maximumManifestBytes: Int64 = 4 * 1024 * 1024
    private static let maximumPayloadBytes: Int64 = 64 * 1024 * 1024
    private static let cryptexPayloads: [(key: String, file: String)] = [
        ("Cryptex1,GenericDmg", "Image.dmg"),
        ("Cryptex1,GenericTrustCache", "Image.dmg.trustcache"),
        ("Cryptex1,CryptexInfoPlist", "Image.dmg.cryptex_info"),
        ("Cryptex1,GenericVolume", "Image.dmg.root_hash"),
    ]

    let documents: URL

    init(documents: URL) {
        self.documents = documents
    }

    /// Same rule as `NativeDeviceSession.mountMethod()`, read from this device.
    static func method(for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Method? {
        guard version.majorVersion >= 26 else { return nil }
        return version.majorVersion > 26 || version.minorVersion >= 4 ? .cryptex : .personalized
    }

    var directory: URL { documents.appendingPathComponent("DDI", isDirectory: true) }

    /// Files this method needs besides `MountMethod`; the image comes last so
    /// the progress total is known before the large transfer starts.
    static func files(for method: Method) -> [String] {
        ["BuildManifest.plist", "Image.dmg.trustcache"]
            + (method == .cryptex ? ["Image.dmg.cryptex_info", "Image.dmg.root_hash"] : [])
            + ["Image.dmg"]
    }

    /// True when a complete local set for `method` exists.
    func hasLocalSupport(method: Method) -> Bool {
        guard (try? String(contentsOf: directory.appendingPathComponent("MountMethod"), encoding: .utf8)) == method.rawValue else {
            return false
        }
        return Self.files(for: method).allSatisfy { name in
            let values = try? directory.appendingPathComponent(name)
                .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? 0) > 0
        }
    }

    /// Downloads when the local set is missing or the mirror publishes a
    /// different build manifest. Returns true when new files were installed.
    /// With a complete local set, an unreachable mirror is not an error.
    /// `force` (settings F11 「重新下載」) always downloads the full set; the
    /// current files stay in place until the new set is published.
    @discardableResult
    func update(method: Method, force: Bool = false, progress: @escaping Progress) async throws -> Bool {
        let hasLocal = !force && hasLocalSupport(method: method)
        let root = Self.baseURL.appendingPathComponent(method == .cryptex ? "Xcode_iOS_DDI_Cryptex" : "Xcode_iOS_DDI_Personalized",
                                                       isDirectory: true)
        let manifest: Data
        do {
            manifest = try await Self.fetch(root.appendingPathComponent("BuildManifest.plist"),
                                            maximum: Self.maximumManifestBytes) { _, _ in }
        } catch {
            if hasLocal { return false }
            throw error
        }
        if hasLocal,
           let local = try? Data(contentsOf: directory.appendingPathComponent("BuildManifest.plist")),
           SHA256.hash(data: local) == SHA256.hash(data: manifest) {
            return false
        }
        try Self.validate(manifest: manifest, method: method)

        var payloads: [String: Data] = ["BuildManifest.plist": manifest]
        var completed = Int64(manifest.count)
        progress(completed, nil)
        for name in Self.files(for: method) where name != "BuildManifest.plist" {
            let base = completed
            let isLast = name == "Image.dmg"
            let data = try await Self.fetch(root.appendingPathComponent(name), maximum: Self.maximumPayloadBytes) { received, expected in
                progress(base + received, isLast && expected > 0 ? base + expected : nil)
            }
            payloads[name] = data
            completed += Int64(data.count)
        }
        progress(completed, completed)
        try publish(payloads, method: method)
        return true
    }

    private static func fetch(_ url: URL, maximum: Int64,
                              progress: @escaping @Sendable (_ received: Int64, _ expected: Int64) -> Void) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let box = DownloadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let task = URLSession.shared.downloadTask(with: request) { location, response, error in
                    box.invalidate()
                    guard error == nil, let location,
                          let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.resume(throwing: SupportDownloadFailure.network)
                        return
                    }
                    guard let data = try? Data(contentsOf: location, options: .mappedIfSafe) else {
                        continuation.resume(throwing: SupportDownloadFailure.storage)
                        return
                    }
                    guard !data.isEmpty, Int64(data.count) <= maximum else {
                        continuation.resume(throwing: SupportDownloadFailure.invalid)
                        return
                    }
                    continuation.resume(returning: data)
                }
                box.observe(task) { received, expected in
                    if expected > maximum { task.cancel() }
                    progress(received, expected)
                }
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// The cryptex manifest must declare the fixed file names we fetch, so
    /// the native loader reads exactly the payloads this download wrote.
    static func validate(manifest: Data, method: Method) throws {
        guard let root = try? PropertyListSerialization.propertyList(from: manifest, format: nil) as? [String: Any],
              let identities = root["BuildIdentities"] as? [[String: Any]], !identities.isEmpty else {
            throw SupportDownloadFailure.invalid
        }
        guard method == .cryptex else { return }
        guard let identity = identities.first(where: {
            (($0["Info"] as? [String: Any])?["Variant"] as? String)?.hasSuffix("Developer Disk Image Cryptex") == true
        }), let entries = identity["Manifest"] as? [String: Any] else { throw SupportDownloadFailure.invalid }
        for payload in cryptexPayloads {
            let path = ((entries[payload.key] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String
            guard path == payload.file else { throw SupportDownloadFailure.invalid }
        }
    }

    /// Writes into a private staging folder, then swaps it in with renames so
    /// a crash leaves either the old complete set or the new one.
    private func publish(_ payloads: [String: Data], method: Method) throws {
        let manager = FileManager.default
        let token = UUID().uuidString
        let staging = documents.appendingPathComponent(".DDI.\(token).staging", isDirectory: true)
        let retired = documents.appendingPathComponent(".DDI.\(token).old", isDirectory: true)
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            for (name, data) in payloads {
                try data.write(to: staging.appendingPathComponent(name),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            try Data(method.rawValue.utf8).write(to: staging.appendingPathComponent("MountMethod"), options: .atomic)
            let existing = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if existing?.isSymbolicLink == true { throw SupportDownloadFailure.storage }
            if existing?.isDirectory == true { try manager.moveItem(at: directory, to: retired) }
            do { try manager.moveItem(at: staging, to: directory) }
            catch {
                if existing?.isDirectory == true { try? manager.moveItem(at: retired, to: directory) }
                throw error
            }
            try? manager.removeItem(at: retired)
        } catch let failure as SupportDownloadFailure {
            try? manager.removeItem(at: staging)
            throw failure
        } catch {
            try? manager.removeItem(at: staging)
            throw SupportDownloadFailure.storage
        }
    }
}

/// Keeps the KVO observation of one download task alive and lets the async
/// caller cancel it.
private final class DownloadTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    func observe(_ task: URLSessionDownloadTask, _ report: @escaping @Sendable (Int64, Int64) -> Void) {
        lock.withLock {
            self.task = task
            observation = task.progress.observe(\.completedUnitCount) { [weak task] _, _ in
                guard let task else { return }
                report(task.countOfBytesReceived, task.countOfBytesExpectedToReceive)
            }
        }
    }

    func invalidate() {
        lock.withLock {
            observation?.invalidate()
            observation = nil
        }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }
}

/// The two steps of the device-support (DDI) modal, shared by onboarding (R04)
/// and the map. Only sideloaded installs without a formal Mac activation use
/// it; Mac-provisioned installs keep their own support and the USB toast.
@MainActor
final class GoFlySupportPreparation: ObservableObject {
    enum Step: Equatable { case download, activate }

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64?)
        case activating
        case failed(Step, messageKey: String)
        case ready
    }

    static let shared = GoFlySupportPreparation()

    @Published private(set) var phase: Phase = .idle
    /// Last download fraction, kept so a failed download shows where it stopped.
    @Published private(set) var downloadFraction: Double = 0
    /// The map's modal; onboarding presents its own from the R04 step.
    @Published var isMapModalPresented = false

    /// Set by the runtime; activation mounts support through `prepare()`.
    var device: (any DeviceService)?
    private var run: Task<Bool, Never>?
    private var mapRetry: (() -> Void)?
    private var lastAutoRetryAt: Date?

    /// Sideloaded builds only; the Mac App installs support itself. Read once:
    /// the runtime starts only after setup has settled.
    private(set) lazy var appliesToThisInstall: Bool = {
        if (Bundle.main.object(forInfoDictionaryKey: "GoFlyRequiresMacSetup") as? Bool) == true { return false }
        guard let setup = try? GoFlySetupPaths.directory() else { return true }
        return (try? SetupActivationStore(directory: setup).activation()) == nil
    }()

    var isRunning: Bool { run != nil }

    /// True when a mountable set exists for this iOS version: the Mac
    /// install's formal set or one downloaded in settings.
    var hasLocalSupport: Bool {
        guard let method = SupportDownloader.method(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        if SupportDownloader(documents: documents).hasLocalSupport(method: method) { return true }
        #if targetEnvironment(simulator)
        return false
        #else
        return ProvisionedSupport.isAvailable(method: method == .cryptex ? .cryptex : .personalized)
        #endif
    }

    /// Starts download then activation unless a run is already in progress.
    /// Returns whether support is ready. `force` re-downloads the full set
    /// (settings F11); a run already in progress is joined instead.
    @discardableResult
    func start(force: Bool = false) async -> Bool {
        if let run { return await run.value }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let ready = await self.perform(force: force)
            self.run = nil
            return ready
        }
        run = task
        return await task.value
    }

    /// Map: show the modal for a device-support error instead of a toast, then
    /// repeat the failed action once support is ready.
    func presentForMap(retry: @escaping () -> Void) {
        guard appliesToThisInstall else { return }
        mapRetry = retry
        isMapModalPresented = true
        // The action failed again right after an automatic retry: show the
        // failure and let the person retry instead of looping.
        if run == nil, let last = lastAutoRetryAt, Date().timeIntervalSince(last) < 5 {
            phase = .failed(.activate, messageKey: "support.activate.error.rejected")
            return
        }
        Task { await startFromMap() }
    }

    func retryFromMap() {
        Task { await startFromMap() }
    }

    /// Closing keeps a running download or activation going; the next error
    /// opens the modal again with the current progress.
    func closeMap() {
        isMapModalPresented = false
        mapRetry = nil
    }

    private func startFromMap() async {
        guard await start(), isMapModalPresented else { return }
        isMapModalPresented = false
        let retry = mapRetry
        mapRetry = nil
        lastAutoRetryAt = Date()
        retry?()
    }

    private func perform(force: Bool = false) async -> Bool {
        guard let method = SupportDownloader.method(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            phase = .failed(.download, messageKey: SupportDownloadFailure.storage.rawValue)
            return false
        }
        phase = .downloading(received: 0, total: nil)
        downloadFraction = 0
        let downloader = SupportDownloader(documents: documents)
        let download = Task.detached(priority: .userInitiated) { () -> Result<Void, SupportDownloadFailure> in
            do {
                try await downloader.update(method: method, force: force) { received, total in
                    Task { @MainActor in
                        GoFlySupportPreparation.shared.reportProgress(received: received, total: total)
                    }
                }
                return .success(())
            } catch let failure as SupportDownloadFailure {
                return .failure(failure)
            } catch {
                return .failure(.network)
            }
        }
        if case .failure(let failure) = await download.value {
            record("download", outcome: failure.rawValue, method: method)
            phase = .failed(.download, messageKey: failure.rawValue)
            return false
        }

        phase = .activating
        do {
            guard let device else { throw DeviceServiceFailure.deviceRequired }
            try await device.prepare()
        } catch {
            let failure = error as? DeviceServiceFailure ?? .serviceUnavailable
            let key = failure.isConnectionFailure ? "support.activate.error.connection"
                : failure == .devicePreparationRequired ? "support.activate.error.rejected" : failure.rawValue
            record("activate", outcome: failure.rawValue, method: method)
            phase = .failed(.activate, messageKey: key)
            return false
        }
        record("activate", outcome: "ready", method: method)
        phase = .ready
        return true
    }

    private func reportProgress(received: Int64, total: Int64?) {
        guard case .downloading = phase else { return }
        phase = .downloading(received: received, total: total)
        if let total, total > 0 { downloadFraction = min(1, Double(received) / Double(total)) }
    }

    private func record(_ step: String, outcome: String, method: SupportDownloader.Method) {
        Diagnostics.shared.record("support.\(step)", category: .device,
                                  level: outcome == "ready" ? .notice : .error,
                                  ["outcome": .text(outcome), "method": .text(method.rawValue)])
    }
}
