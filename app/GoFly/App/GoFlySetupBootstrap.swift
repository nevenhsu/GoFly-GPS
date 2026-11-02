import CryptoKit
import Darwin
import Foundation
import GoFlyCore
import SwiftUI

enum GoFlySetupBootstrapPhase: Equatable {
    case preparing
    case ordinaryStartup
    case awaitingMacInstall
    case awaitingPairingImport
    case waitingForMac(SetupReadbackRequest)
    case completed(SetupReceipt)
    case blocked(SetupFailure)
}

struct GoFlySetupMetadata: Equatable, Sendable {
    let teamID: String
    let signingExpiry: String

    init(receipt: SetupReceipt) {
        teamID = receipt.teamID
        signingExpiry = receipt.signingExpiry
    }
}

/// Owns only the formal setup check until it has produced an ordinary or
/// completed result. The normal runtime assembly is retained exactly once and
/// is created on the main actor only after that result.
@MainActor
final class GoFlySetupBootstrap: ObservableObject {
    @Published private(set) var phase: GoFlySetupBootstrapPhase = .preparing
    private(set) var runtime: GoFlyRuntimeAssembly?
    private(set) var metadata: GoFlySetupMetadata?
    var startupTask: Task<Void, Never>?

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if GoFlyUITestOverrides.frame != nil {
            if GoFlyUITestOverrides.frameNeedsMapRuntime {
                runtime = GoFlyRuntimeAssembly()
            }
            phase = .ordinaryStartup
            return
        }
        #endif
        start()
    }

    deinit {
        startupTask?.cancel()
    }

    func retry() {
        guard case .blocked = phase else { return }
        start()
    }

    func refreshPendingMacSetup() {
        switch phase {
        case .awaitingMacInstall, .waitingForMac:
            start()
        default:
            break
        }
    }

    /// R07.s: re-runs the setup check once a sideload pairing import commits.
    func pairingImported() {
        guard case .awaitingPairingImport = phase else { return }
        start()
    }

    private func start() {
        startupTask?.cancel()
        if case .blocked = phase {
            runtime = nil
            metadata = nil
        }
        phase = .preparing

        #if targetEnvironment(simulator)
        let requiresMacSetup = false
        let requiresPairingImport = false
        #else
        let requiresMacSetup = (Bundle.main.object(forInfoDictionaryKey: "GoFlyRequiresMacSetup") as? Bool) == true
        // The sideload IPA (flag false) has no Mac handoff; it asks for the
        // iloader pairing file instead (R07.s).
        let requiresPairingImport = !requiresMacSetup
        #endif

        startupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    let store = SetupActivationStore(directory: try GoFlySetupPaths.directory())
                    try store.prepareIncomingFiles()
                    let coordinator = SetupBootstrapCoordinator(
                        store: store,
                        pairing: GoFlySetupPairingAdapter()
                    )
                    let setup = try coordinator.prepare(
                        bundleID: GoFlySetupIdentityReader.readBundleID,
                        identity: GoFlySetupIdentityReader.readFullIdentity
                    )
                    if requiresMacSetup, case .ordinaryStartup = setup {
                        return GoFlyBootstrapOutcome.awaitingMacInstall
                    }
                    if requiresPairingImport, case .ordinaryStartup = setup, !PairingFileStore.isReady {
                        return GoFlyBootstrapOutcome.awaitingPairingImport
                    }
                    switch setup {
                    case .ordinaryStartup: return .ordinary
                    case .waitingForMac(let request): return .waitingForMac(request)
                    case .blocked(let failure): return .blocked(failure)
                    case .completed(let receipt): return .completed(receipt)
                    }
                } catch let failure as SetupFailure {
                    return .blocked(failure)
                } catch {
                    return .blocked(.storageUnavailable)
                }
            }.value
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    private func apply(_ result: GoFlyBootstrapOutcome) {
        switch result {
        case .ordinary:
            runtime = GoFlyRuntimeAssembly()
            phase = .ordinaryStartup
        case .completed(let receipt):
            GoFlyPreferences.shared.refreshPersistedValues()
            runtime = GoFlyRuntimeAssembly()
            metadata = GoFlySetupMetadata(receipt: receipt)
            phase = .completed(receipt)
        case .waitingForMac(let request):
            phase = .waitingForMac(request)
        case .awaitingMacInstall:
            phase = .awaitingMacInstall
        case .awaitingPairingImport:
            phase = .awaitingPairingImport
        case .blocked(let failure):
            phase = .blocked(failure)
        }
    }
}

private enum GoFlyBootstrapOutcome: Sendable {
    case ordinary
    case completed(SetupReceipt)
    case waitingForMac(SetupReadbackRequest)
    case awaitingMacInstall
    case awaitingPairingImport
    case blocked(SetupFailure)
}

enum GoFlySetupIdentityReader {
    /// Ordinary launch reads only the bundle ID; it never hashes the
    /// executable or profile.
    static func readBundleID() throws -> String {
        guard let bundleID = Bundle.main.bundleIdentifier,
              SetupAppIdentity.isGoFlyBundleID(bundleID) else {
            throw SetupFailure.identityMismatch
        }
        return bundleID
    }

    /// The Mac readback handshake is the only caller that binds the full
    /// installed product, so only this path computes the bounded hashes.
    static func readFullIdentity() throws -> SetupAppIdentity {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty,
              let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let executable = Bundle.main.executableURL else {
            throw SetupFailure.identityMismatch
        }

        return try SetupAppIdentity(
            bundleID: try readBundleID(),
            build: build,
            profileSHA256: try SHA256FileHasher.hex(profile, maximumBytes: 4 * 1_024 * 1_024),
            executableSHA256: try SHA256FileHasher.hex(executable, maximumBytes: 256 * 1_024 * 1_024)
        )
    }
}

private enum SHA256FileHasher {
    static func hex(_ url: URL, maximumBytes: Int) throws -> String {
        let fd = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw SetupFailure.identityMismatch }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 0,
              info.st_size <= maximumBytes else {
            throw SetupFailure.identityMismatch
        }

        var digest = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress, $0.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SetupFailure.identityMismatch }
            if count == 0 { break }
            total += count
            guard total <= maximumBytes else { throw SetupFailure.limitExceeded }
            digest.update(data: Data(buffer.prefix(count)))
        }
        guard total == Int(info.st_size) else { throw SetupFailure.identityMismatch }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Bridges the frozen v1 handoff to the existing protected pairing store. All
/// observations are bounded and no-follow; LocalGoSetupHandoff remains the
/// single importer and receipt writer.
private struct GoFlySetupPairingAdapter: SetupPairingAccess {
    private let handoffDirectory: URL

    init(fileManager: FileManager = .default) {
        handoffDirectory = LocalGoSetupHandoff.defaultDirectory(fileManager: fileManager)
    }

    func prepare() throws {
        _ = try LocalGoSetupHandoff.prepare(directory: handoffDirectory)
        try Self.sealIncomingFile(in: handoffDirectory)
        _ = PairingFileStore.prepareURL()
    }

    func observeStoredPairing(expectedDeviceUDID: String) throws -> SetupPairingObservation {
        let rawURL = PairingFileStore.url
        guard try Self.present(rawURL) || Self.present(
            rawURL.deletingLastPathComponent().appendingPathComponent("pairingFile.envelope.plist")
        ) else {
            return .absent
        }
        guard PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expectedDeviceUDID),
              let data = try Self.read(rawURL, maximum: 1 * 1_024 * 1_024) else {
            return .invalid
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .verified(expectedDeviceUDID: expectedDeviceUDID.lowercased(), sha256: hash)
    }

    func observe(for input: SetupInput) throws -> SetupPairingEvidence {
        let stored = try observeStoredPairing(expectedDeviceUDID: input.manifest.expectedDeviceUDID)
        let inputObservation = try observeInput(for: input)
        let receiptObservation = try observeReceipt(for: input.manifest.pairingTransactionID)
        return SetupPairingEvidence(stored: stored, input: inputObservation, receipt: receiptObservation)
    }

    func consumeExactPending(for input: SetupInput) throws {
        guard try observeInput(for: input) == .exact,
              try observeReceipt(for: input.manifest.pairingTransactionID) == .absent else {
            throw SetupFailure.pairingRejected
        }

        let expectedDeviceUDID = input.manifest.expectedDeviceUDID
        let expectedPairingSHA256 = input.manifest.pairingSHA256
        let handoff = LocalGoSetupHandoff(directory: handoffDirectory) { pairingData, receivedDeviceUDID in
            guard receivedDeviceUDID.lowercased() == expectedDeviceUDID,
                  Self.hex(Data(SHA256.hash(data: pairingData))) == expectedPairingSHA256 else {
                throw SetupFailure.pairingRejected
            }
            if PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expectedDeviceUDID),
               let existing = try? Self.read(PairingFileStore.url, maximum: LocalGoSetupProtocol.maximumPairingFileBytes),
               SHA256.hash(data: existing) == SHA256.hash(data: pairingData) {
                return
            }
            try PairingFileStore.importSetupData(pairingData, expectedDeviceUDID: receivedDeviceUDID)
        }

        switch handoff.consume(
            commandsIdle: true,
            isPreparing: false,
            expectedTransactionID: input.manifest.pairingTransactionID
        ) {
        case .imported: return
        case .rejected: throw SetupFailure.pairingRejected
        case .storageFailure: throw SetupFailure.storageUnavailable
        case .noPayload: throw SetupFailure.pairingUnknown
        }
    }

    private func observeInput(for input: SetupInput) throws -> SetupV1InputObservation {
        guard let data = try Self.read(
            handoffDirectory.appendingPathComponent(LocalGoSetupHandoff.incomingFileName),
            maximum: LocalGoSetupProtocol.maximumIncomingFileBytes
        ) else { return .absent }

        guard let payload = try? LocalGoSetupProtocol.decodeIncoming(data),
              payload.transactionID == input.manifest.pairingTransactionID,
              payload.expectedDeviceUDID == input.manifest.expectedDeviceUDID,
              Self.hex(payload.sha256) == input.manifest.pairingSHA256 else {
            return .malformedOrMismatched
        }
        return .exact
    }

    private func observeReceipt(for transactionID: UUID) throws -> SetupV1ReceiptObservation {
        let receiptsDirectory = handoffDirectory.appendingPathComponent(LocalGoSetupHandoff.receiptsDirectoryName)
        guard try Self.present(receiptsDirectory) else { return .absent }
        guard Self.isPrivateDirectory(receiptsDirectory) else { throw SetupFailure.unsafeFile }

        let entries = try Self.directoryEntries(
            receiptsDirectory,
            maximum: LocalGoSetupProtocol.maximumReceiptCount
        )

        var found: LocalGoSetupProtocol.Receipt?
        var seenTransactions = Set<UUID>()
        for entry in entries {
            guard entry.pathExtension == "plist",
                  let name = entry.deletingPathExtension().lastPathComponent.lowercased() as String?,
                  UUID(uuidString: name)?.uuidString.lowercased() == name,
                  let data = try Self.read(entry, maximum: 64 * 1_024) else {
                throw SetupFailure.pairingRejected
            }
            guard let receipt = try? LocalGoSetupProtocol.decodeReceipt(data),
                  receipt.transactionID.uuidString.lowercased() == name else {
                throw SetupFailure.pairingRejected
            }
            guard seenTransactions.insert(receipt.transactionID).inserted else {
                throw SetupFailure.pairingRejected
            }
            if receipt.transactionID == transactionID { found = receipt }
        }

        guard let found else { return .absent }
        return found.status == .success ? .success : .rejectedOrMalformed
    }

    private static func present(_ url: URL) throws -> Bool {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else {
            if errno == ENOENT { return false }
            throw SetupFailure.storageUnavailable
        }
        return true
    }

    private static func isPrivateDirectory(_ url: URL) -> Bool {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var info = stat()
        return fstat(fd, &info) == 0 &&
            info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
            info.st_uid == geteuid() && info.st_mode & mode_t(0o7777) == mode_t(0o700)
    }

    /// AFC cannot set permissions on the incoming handoff. Seal only that
    /// fixed file after the existing handoff prepares its private root; the
    /// bytes, replay state, and receipts remain owned by LocalGo's consumer.
    private static func sealIncomingFile(in directory: URL) throws {
        let root = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard root >= 0 else { throw SetupFailure.storageUnavailable }
        defer { Darwin.close(root) }

        var rootInfo = stat()
        guard fstat(root, &rootInfo) == 0,
              rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootInfo.st_uid == geteuid(),
              rootInfo.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            throw SetupFailure.unsafeFile
        }

        let incoming = LocalGoSetupHandoff.incomingFileName
        let fd = incoming.withCString {
            openat(root, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ENOENT { return }
            throw SetupFailure.storageUnavailable
        }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_nlink == 1,
              info.st_size > 0,
              info.st_size <= LocalGoSetupProtocol.maximumIncomingFileBytes else {
            throw SetupFailure.unsafeFile
        }
        let permissions = info.st_mode & mode_t(0o7777)
        guard permissions == mode_t(0o600) || permissions == mode_t(0o644) else {
            throw SetupFailure.unsafeFile
        }
        guard fchmod(fd, mode_t(0o600)) == 0,
              fsync(fd) == 0 else {
            throw SetupFailure.storageUnavailable
        }
    }

    private static func directoryEntries(_ url: URL, maximum: Int) throws -> [URL] {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw SetupFailure.storageUnavailable }
        guard let stream = fdopendir(fd) else {
            Darwin.close(fd)
            throw SetupFailure.storageUnavailable
        }
        defer { closedir(stream) }

        var names: [String] = []
        names.reserveCapacity(min(maximum, 32))
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            names.append(name)
            guard names.count <= maximum else { throw SetupFailure.limitExceeded }
            errno = 0
        }
        guard errno == 0 else { throw SetupFailure.storageUnavailable }
        return names.map { url.appendingPathComponent($0, isDirectory: false) }
    }

    private static func read(_ url: URL, maximum: Int) throws -> Data? {
        let fd = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw SetupFailure.storageUnavailable
        }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o600),
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= maximum else { throw SetupFailure.unsafeFile }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SetupFailure.storageUnavailable }
            if count == 0 {
                guard data.count == Int(info.st_size) else { throw SetupFailure.storageUnavailable }
                return data
            }
            guard data.count + count <= maximum else { throw SetupFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

struct GoFlySetupLockView: View {
    let phase: GoFlySetupBootstrapPhase
    let onRetry: () -> Void

    var body: some View {
        Group {
            if case .blocked(.identityMismatch) = phase {
                identityMismatchPage
            } else {
                fallbackPage
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var identityMismatchPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoFlyOnboardingEmblem(symbol: .gear)
                    .accessibilityIdentifier("setup.blocked.hero")
                Text(goFlyString(titleKey))
                    .goFlyFont(GoFlyFont.display)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
                    .accessibilityIdentifier("setup.blocked.title")
                Text(goFlyString(messageKey))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 287)
                    .padding(.top, 13)
                    .accessibilityIdentifier("setup.blocked.identity")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 131)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
    }

    private var fallbackPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GoFlyIcon(iconName)
                    .goFlyIconSize(size: 44, maximum: 56)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .accessibilityHidden(true)
                Text(goFlyString(titleKey))
                    .goFlyFont(GoFlyFont.title)
                Text(goFlyString(messageKey))
                    .goFlyFont(GoFlyFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                if case .blocked = phase {
                    Button(action: onRetry) {
                        Text(goFlyString("setup.retry"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(GoFlyButtonStyle(variant: .primary))
                    .accessibilityIdentifier("setup.retry")
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
    }

    private var titleKey: String {
        switch phase {
        case .preparing: return "setup.preparing.title"
        case .ordinaryStartup, .awaitingPairingImport: return "setup.preparing.title"
        case .awaitingMacInstall, .waitingForMac: return "setup.waiting.title"
        case .completed: return "setup.completed.title"
        case .blocked: return "setup.blocked.title"
        }
    }

    private var messageKey: String {
        switch phase {
        case .preparing: return "setup.preparing.message"
        case .ordinaryStartup, .awaitingPairingImport: return "setup.preparing.message"
        case .awaitingMacInstall, .waitingForMac: return "setup.waiting.message"
        case .completed: return "setup.completed.message"
        case .blocked(let failure): return failure.messageKey
        }
    }

    private var iconName: GoFlyIconAsset {
        switch phase {
        case .blocked: return .shield
        case .awaitingMacInstall, .waitingForMac: return .mac
        default: return .select
        }
    }

    private var accessibilityIdentifier: String {
        switch phase {
        case .preparing, .awaitingPairingImport: return "setup.preparing"
        case .ordinaryStartup, .completed: return "setup.ready"
        case .awaitingMacInstall, .waitingForMac: return "setup.waiting"
        case .blocked: return "setup.blocked"
        }
    }
}

/// R07 is the formal first-install handoff screen. The Mac completes pairing
/// and setup while GoFly is inactive; returning to the app refreshes bootstrap.
struct GoFlyMacSetupOnboardingView: View {
    var body: some View {
        GoFlySetupHeroPage(icon: .mac, titleKey: "setup.mac.title", messageKey: "setup.mac.message",
                           statusKey: "setup.mac.unpaired", statusIdentifier: "setup.mac.status")
            .accessibilityIdentifier("setup.mac")
    }
}

/// Shared R07 / R07.s layout: hero icon, title, message and neutral status pill.
private struct GoFlySetupHeroPage: View {
    let icon: GoFlyIconAsset
    let titleKey: String
    let messageKey: String
    let statusKey: String
    let statusIdentifier: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoFlyIcon(icon)
                    .goFlyIconSize(size: 48, maximum: 60)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 120, height: 120)
                    .background(
                        GoFlyStyle.onboardingHeroSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 36, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text(goFlyString(titleKey))
                    .goFlyFont(GoFlyFont.display)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                Text(goFlyString(messageKey))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 287)
                    .padding(.top, 13)

                GoFlyStatusPill(text: goFlyString(statusKey), tone: .neutral, identifier: statusIdentifier)
                    .padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 136)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
    }
}

/// R07.s: the sideload IPA's first step. Imports a pairing file exported on a computer;
/// the Mac build keeps R07.
struct GoFlyPairingImportView: View {
    let onImported: () -> Void
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var importFailed = false

    var body: some View {
        GoFlySetupHeroPage(icon: .phone, titleKey: "setup.pairingImport.title",
                           messageKey: "setup.pairingImport.message",
                           statusKey: "setup.pairingImport.notImported",
                           statusIdentifier: "setup.pairingImport.status")
        .goFlyToastOverlay(topInset: 64) {
            if importFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyIssueTitle(for: "setup.pairingImport.failed"), message: goFlyString("setup.pairingImport.failed"),
                                  identifier: "setup.pairingImport.failed")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                importFailed = false
                showingImporter = true
            } label: {
                HStack(spacing: 8) {
                    if isImporting { ProgressView() }
                    Text(goFlyString("setup.pairingImport.action"))
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .disabled(isImporting)
            .accessibilityIdentifier("setup.pairingImport.action")
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(GoFlyStyle.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { GoFlyThemeColor.lineSeparator.frame(height: 0.5) }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: PairingFileStore.supportedContentTypes) { result in
            // Cancelling the picker keeps this page unchanged.
            guard case .success(let url) = result else { return }
            importPairing(from: url)
        }
        .accessibilityIdentifier("setup.pairingImport")
    }

    private func importPairing(from url: URL) {
        isImporting = true
        Task {
            // Native validation reads the file through the FFI, off the main actor.
            let imported = await Task.detached(priority: .userInitiated) {
                (try? PairingFileStore.importSideloadedPairing(url)) != nil
            }.value
            isImporting = false
            if imported {
                onImported()
            } else {
                importFailed = true
            }
        }
    }
}

private extension SetupFailure {
    var messageKey: String {
        switch self {
        case .identityMismatch: return "setup.blocked.identity"
        case .pairingUnknown, .pairingRejected: return "setup.blocked.pairing"
        case .artifactMismatch: return "setup.blocked.artifact"
        case .invalidInput, .unsupportedVersion: return "setup.blocked.input"
        default: return "setup.blocked.storage"
        }
    }
}

/// Matches LaunchScreen while the setup check runs off the main actor.
struct GoFlyStartupView: View {
    @State private var showsProgress = false

    var body: some View {
        GeometryReader { geometry in
            let midX = geometry.size.width / 2
            let midY = geometry.size.height / 2
            ZStack {
                GoFlyStyle.canvas.ignoresSafeArea()
                // The asset carries the Light (black tile) and Dark (white tile) logo.
                Image("GoFlyLogo")
                    .resizable()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24.5, style: .continuous))
                    .position(x: midX, y: midY - 48)

                Text("GoFly GPS")
                    .goFlyFont(GoFlyFont.display)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 220, height: 34)
                    .position(x: midX, y: midY + 41)

                if showsProgress {
                    ProgressView(value: 0.70)
                        .progressViewStyle(GoFlyProgressStyle())
                        .frame(width: 101)
                        .position(x: midX, y: midY + 96)
                        .accessibilityLabel(goFlyString("setup.preparing.message"))
                        .accessibilityIdentifier("setup.preparing.progress")
                }
            }
            .accessibilityElement(children: .contain)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("setup.preparing")
        .task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            showsProgress = true
        }
    }
}
