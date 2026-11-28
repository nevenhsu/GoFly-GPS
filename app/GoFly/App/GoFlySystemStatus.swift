import Combine
import CoreLocation
import GoFlyCore
import MachO
import SQLite3
import UIKit

/// Reads system status for the settings pages. Constructing this model never
/// asks for location access, opens another app, or creates a device session.
@MainActor
final class GoFlySystemStatus: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var locationAuthorization: CLAuthorizationStatus
    @Published private(set) var locationServicesEnabled: Bool?
    @Published private(set) var backgroundRefreshStatus: UIBackgroundRefreshStatus
    @Published private(set) var pairingReady: Bool?
    @Published private(set) var externalOpenFailed = false
    @Published private(set) var localSigningInfo: EmbeddedSigningInfo?
    @Published private(set) var misagentSigningInfo: EmbeddedSigningInfo?

    private let locationManager: CLLocationManager
    private var servicesQueryTask: Task<Void, Never>?
    private var pairingReadyQueryTask: Task<Void, Never>?
    private var misagentQueryTask: Task<Void, Never>?
    private var backgroundRefreshCancellable: AnyCancellable?

    override init() {
        locationManager = CLLocationManager()
        locationAuthorization = locationManager.authorizationStatus
        locationServicesEnabled = nil
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        pairingReady = nil
        super.init()
        locationManager.delegate = self
        backgroundRefreshCancellable = NotificationCenter.default
            .publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
            }
        refresh()
    }

    deinit {
        servicesQueryTask?.cancel()
        pairingReadyQueryTask?.cancel()
        misagentQueryTask?.cancel()
    }

    var locationStatusKey: String {
        guard let locationServicesEnabled else { return "settings.status.unknown" }
        guard locationServicesEnabled else { return "settings.status.locationServicesOff" }
        switch locationAuthorization {
        case .authorizedAlways: return "settings.status.always"
        case .authorizedWhenInUse: return "settings.status.authorized"
        case .denied: return "settings.status.denied"
        case .restricted: return "settings.status.restricted"
        case .notDetermined: return "settings.status.notDetermined"
        @unknown default: return "settings.status.unknown"
        }
    }

    var backgroundStatusKey: String {
        switch backgroundRefreshStatus {
        case .available: return "settings.background.on"
        case .denied: return "settings.background.off"
        case .restricted: return "settings.status.restricted"
        @unknown default: return "settings.status.unknown"
        }
    }

    /// UIKit's `backgroundRefreshStatus` queries by `Bundle.main.bundleIdentifier`.
    /// When LiveContainer spoofs the guest bundle ID, avoid displaying a misleading
    /// On/Off value from another bundle and show the host container name instead.
    var backgroundStatusText: String {
        if GoFlyLiveContainerHost.usesSpoofedBundleIdentifier,
           let containerName = GoFlyLiveContainerHost.hostDisplayName {
            return containerName
        }
        return goFlyString(backgroundStatusKey)
    }

    func refresh() {
        locationAuthorization = locationManager.authorizationStatus
        if servicesQueryTask == nil {
            servicesQueryTask = Task { @MainActor [weak self] in
                let enabled = await Task.detached(priority: .utility) {
                    CLLocationManager.locationServicesEnabled()
                }.value
                guard let self else { return }
                self.locationServicesEnabled = enabled
                self.servicesQueryTask = nil
            }
        }
        if pairingReadyQueryTask == nil {
            pairingReadyQueryTask = Task { @MainActor [weak self] in
                let ready = await Task.detached(priority: .utility) {
                    PairingFileStore.isReady
                }.value
                guard let self else { return }
                self.pairingReady = ready
                self.pairingReadyQueryTask = nil
            }
        }
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    /// Opens the actual system settings URL and records only whether the OS
    /// accepted the open request. Returning to the app triggers a fresh read.
    func openSystemSettings() {
        externalOpenFailed = false
        GoFlyExternalLinks.openAppSettings { [weak self] opened in
            self?.externalOpenFailed = !opened
        }
    }

    func openLocalDevVPN() {
        externalOpenFailed = false
        GoFlyExternalLinks.openLocalDevVPN { [weak self] opened in
            self?.externalOpenFailed = !opened
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func deviceSnapshot(service: ServiceController, setupMetadata: GoFlySetupMetadata? = nil) -> GoFlyDeviceSnapshot {
        let fallback: EmbeddedSigningInfo?
        if let setupMetadata, setupMetadata.signingExpiry != nil, setupMetadata.teamID != nil {
            // Formal Mac install receipt is authoritative and preserved as-is.
            fallback = nil
        } else {
            let local = localSigningInfo ?? resolvedEmbeddedSigningInfo
            fallback = Self.mergedSigningInfo(local, misagentSigningInfo)
        }
        return GoFlyDeviceSnapshot(
            pairingReady: pairingReady,
            pairingVerification: service.pairingVerification,
            pairingVerified: service.pairingVerified,
            signingExpiry: setupMetadata?.signingExpiry ?? fallback?.signingExpiry,
            teamID: setupMetadata?.teamID ?? fallback?.teamID,
            serviceStatus: goFlyString(service.statusKey),
            appVersion: Self.appVersion,
            deviceName: UIDevice.current.name,
            deviceModel: UIDevice.current.model,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    /// Refreshes sideload signing metadata for F9 (Device and Signing).
    /// Skipped for formal Mac installs (`hasSetupMetadata == true`) so their
    /// receipt stays authoritative. For sideloads (standalone SideStore/AltStore
    /// and LiveContainer), reads local `embedded.mobileprovision` + built-in
    /// SideStore `AltStore.sqlite`, and when LocalDevVPN is reachable also
    /// queries system-installed provisioning profiles via `misagent`.
    func refreshDeviceSigningInfo(hasSetupMetadata: Bool) {
        guard !hasSetupMetadata else { return }
        localSigningInfo = Self.readEmbeddedSigningInfo()
        #if !targetEnvironment(simulator)
        guard misagentQueryTask == nil else { return }
        let localProfile = Self.firstLocalProvisioningProfile()
        misagentQueryTask = Task { @MainActor [weak self] in
            let info = await Task.detached(priority: .utility) {
                Self.readMisagentSigningInfo(localProfile: localProfile)
            }.value
            guard let self else { return }
            if let info {
                self.misagentSigningInfo = info
            }
            self.misagentQueryTask = nil
        }
        #endif
    }

    struct EmbeddedSigningInfo: Sendable {
        let signingExpiry: String?
        let teamID: String?
    }

    private struct ParsedProvisioningProfile: Sendable {
        let expirationDate: Date?
        let teamID: String?
        let applicationIdentifier: String?
        let appGroups: [String]
    }

    private lazy var resolvedEmbeddedSigningInfo: EmbeddedSigningInfo? = Self.readEmbeddedSigningInfo()

    private static func mergedSigningInfo(_ a: EmbeddedSigningInfo?, _ b: EmbeddedSigningInfo?) -> EmbeddedSigningInfo? {
        switch (a, b) {
        case let (nil, other), let (other, nil):
            return other
        case let (first?, second?):
            let formatter = ISO8601DateFormatter()
            let firstDate = first.signingExpiry.flatMap { formatter.date(from: $0) }
            let secondDate = second.signingExpiry.flatMap { formatter.date(from: $0) }
            let signingExpiry: String? = switch (firstDate, secondDate) {
            case let (d1?, d2?): d2 > d1 ? second.signingExpiry : first.signingExpiry
            case (_?, nil): first.signingExpiry
            case (nil, _?): second.signingExpiry
            case (nil, nil): first.signingExpiry ?? second.signingExpiry
            }
            let teamID = first.teamID ?? second.teamID
            return EmbeddedSigningInfo(signingExpiry: signingExpiry, teamID: teamID)
        }
    }

    private static func firstLocalProvisioningProfile() -> ParsedProvisioningProfile? {
        for url in candidateProvisioningProfileURLs() {
            if let parsed = parseProvisioningProfile(at: url) {
                return parsed
            }
        }
        return nil
    }

    /// Reads signing metadata from `embedded.mobileprovision` and, when running
    /// inside LiveContainer with built-in SideStore, checks `AltStore.sqlite`
    /// read-only so profile-only refreshes (which do not overwrite the host
    /// `.app` bundle's `embedded.mobileprovision`) still show the latest expiry.
    private static func readEmbeddedSigningInfo() -> EmbeddedSigningInfo? {
        let parsedProfile = firstLocalProvisioningProfile()

        let sideStoreExpiry = readBuiltInSideStoreExpirationDate(profile: parsedProfile)
        let bestExpiryDate: Date? = switch (parsedProfile?.expirationDate, sideStoreExpiry) {
        case let (a?, b?): max(a, b)
        case let (a?, nil): a
        case let (nil, b?): b
        case (nil, nil): nil
        }

        let signingExpiry: String? = bestExpiryDate.map { formatISO8601($0) }
        let teamID = parsedProfile?.teamID

        guard signingExpiry != nil || teamID != nil else { return nil }
        return EmbeddedSigningInfo(signingExpiry: signingExpiry, teamID: teamID)
    }

    nonisolated private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    #if !targetEnvironment(simulator)
    nonisolated private static func readMisagentSigningInfo(localProfile: ParsedProvisioningProfile?) -> EmbeddedSigningInfo? {
        guard let rawProfiles = NativeDeviceSession.fetchProvisioningProfiles(), !rawProfiles.isEmpty else {
            return nil
        }
        let targetAppIDs = candidateApplicationIdentifiers(profile: localProfile)
        let targetBundleIDs = Set(candidateHostBundleIdentifiers(profile: localProfile))
        let targetTeamID = localProfile?.teamID
        guard !targetAppIDs.isEmpty || !targetBundleIDs.isEmpty else { return nil }

        var bestDate: Date?
        var bestTeamID: String?
        for raw in rawProfiles {
            guard let parsed = parseProvisioningProfile(data: raw),
                  let expDate = parsed.expirationDate else { continue }
            guard matchesCurrentApp(
                parsed,
                targetAppIDs: targetAppIDs,
                targetBundleIDs: targetBundleIDs,
                targetTeamID: targetTeamID
            ) else { continue }
            if bestDate == nil || expDate > bestDate! {
                bestDate = expDate
                bestTeamID = parsed.teamID ?? bestTeamID
            }
        }
        guard let bestDate else { return nil }
        return EmbeddedSigningInfo(signingExpiry: formatISO8601(bestDate), teamID: bestTeamID ?? targetTeamID)
    }

    nonisolated private static func candidateApplicationIdentifiers(profile: ParsedProvisioningProfile?) -> Set<String> {
        var appIDs: Set<String> = []
        if let appID = profile?.applicationIdentifier, !appID.isEmpty {
            appIDs.insert(appID)
        }
        if let teamID = profile?.teamID, !teamID.isEmpty {
            for bundleID in candidateHostBundleIdentifiers(profile: profile) {
                appIDs.insert("\(teamID).\(bundleID)")
            }
        }
        return appIDs
    }

    nonisolated private static func matchesCurrentApp(
        _ candidate: ParsedProvisioningProfile,
        targetAppIDs: Set<String>,
        targetBundleIDs: Set<String>,
        targetTeamID: String?
    ) -> Bool {
        if let appID = candidate.applicationIdentifier, targetAppIDs.contains(appID) {
            return true
        }
        if let targetTeamID, let candidateTeam = candidate.teamID, candidateTeam != targetTeamID {
            return false
        }
        guard let appID = candidate.applicationIdentifier,
              let dot = appID.firstIndex(of: ".") else { return false }
        let stripped = String(appID[appID.index(after: dot)...])
        // Never match wildcard profiles (`*`) from unrelated apps.
        guard stripped != "*", !stripped.contains("*") else { return false }
        return targetBundleIDs.contains(stripped)
    }
    #endif

    private static func candidateProvisioningProfileURLs() -> [URL] {
        var urls: [URL] = []
        func appendUnique(_ url: URL) {
            if !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                urls.append(url)
            }
        }
        if let bundleProfile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") {
            appendUnique(bundleProfile)
        }
        if let hostProfile = liveContainerHostBundle()?.url(forResource: "embedded", withExtension: "mobileprovision") {
            appendUnique(hostProfile)
        }
        for hostBundleURL in hostBundleURLsFromLoadedImages() {
            appendUnique(hostBundleURL.appendingPathComponent("embedded.mobileprovision"))
        }
        if let hostProfile = hostExecutableBundleURL()?.appendingPathComponent("embedded.mobileprovision") {
            appendUnique(hostProfile)
        }
        return urls
    }

    /// LiveContainer hooks both `Bundle.main` and `_NSGetExecutablePath` to
    /// spoof the guest app bundle, while preserving the host bundle on
    /// `+[NSUserDefaults lcMainBundle]`.
    nonisolated private static func liveContainerHostBundle() -> Bundle? {
        GoFlyLiveContainerHost.hostBundle()
    }

    /// Fallback for containerized hosts whose own frameworks/dylibs are loaded
    /// from the real signed host `.app` under `/containers/Bundle/Application/`.
    private static func hostBundleURLsFromLoadedImages() -> [URL] {
        var bundles: [URL] = []
        var seen: Set<String> = []
        let marker = "/containers/Bundle/Application/"
        let count = _dyld_image_count()
        for index in 0..<count {
            guard let cPath = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cPath)
            guard let markerRange = path.range(of: marker) else { continue }
            let afterMarker = path[markerRange.upperBound...]
            guard let appRange = afterMarker.range(of: ".app/", options: .caseInsensitive) else { continue }
            let bundlePath = String(path[..<appRange.upperBound].dropLast())
            if seen.insert(bundlePath).inserted {
                bundles.append(URL(fileURLWithPath: bundlePath, isDirectory: true))
            }
        }
        return bundles
    }

    private static func hostExecutableBundleURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0, size <= 16_384 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        let path = String(cString: buffer)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    private static func parseProvisioningProfile(at url: URL) -> ParsedProvisioningProfile? {
        let maxBytes = 4 * 1_024 * 1_024
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0, fileSize <= maxBytes,
              let raw = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return parseProvisioningProfile(data: raw)
    }

    nonisolated private static func parseProvisioningProfile(data raw: Data) -> ParsedProvisioningProfile? {
        let startMarker = Data("<plist".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let startRange = raw.range(of: startMarker),
              let endRange = raw.range(of: endMarker, in: startRange.lowerBound..<raw.endIndex) else {
            return nil
        }

        let plistData = raw.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any] else {
            return nil
        }

        let expirationDate = plist["ExpirationDate"] as? Date
        let entitlements = plist["Entitlements"] as? [String: Any]
        let teamCandidates: [String?] = [
            (plist["TeamIdentifier"] as? [String])?.first,
            entitlements?["com.apple.developer.team-identifier"] as? String,
            (plist["ApplicationIdentifierPrefix"] as? [String])?.first
        ]
        let teamID = teamCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let applicationIdentifier = (entitlements?["application-identifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appGroups = (entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard expirationDate != nil || teamID != nil else { return nil }
        return ParsedProvisioningProfile(
            expirationDate: expirationDate,
            teamID: teamID,
            applicationIdentifier: applicationIdentifier,
            appGroups: appGroups
        )
    }

    /// Reads the host app's latest `ZEXPIRATIONDATE` from built-in SideStore's
    /// `AltStore.sqlite` inside LiveContainer's App Group (read-only).
    private static func readBuiltInSideStoreExpirationDate(profile: ParsedProvisioningProfile?) -> Date? {
        let hostBundleIDs = candidateHostBundleIdentifiers(profile: profile)
        guard !hostBundleIDs.isEmpty else { return nil }

        var latestDate: Date?
        for dbURL in candidateSideStoreDatabaseURLs(profile: profile) {
            if let date = querySideStoreExpirationDate(at: dbURL, bundleIdentifiers: hostBundleIDs) {
                if let current = latestDate {
                    latestDate = max(current, date)
                } else {
                    latestDate = date
                }
            }
        }
        return latestDate
    }

    nonisolated private static func candidateHostBundleIdentifiers(profile: ParsedProvisioningProfile?) -> [String] {
        var ids: [String] = []
        func appendID(_ raw: String?) {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return }
            if !ids.contains(trimmed) {
                ids.append(trimmed)
            }
            if let teamID = profile?.teamID, !teamID.isEmpty, trimmed.hasSuffix(".\(teamID)") {
                let withoutTeam = String(trimmed.dropLast(teamID.count + 1))
                if !withoutTeam.isEmpty, !ids.contains(withoutTeam) {
                    ids.append(withoutTeam)
                }
            }
        }

        appendID(liveContainerHostBundle()?.bundleIdentifier)
        appendID(Bundle.main.bundleIdentifier)
        if let appID = profile?.applicationIdentifier {
            if let teamID = profile?.teamID, !teamID.isEmpty, appID.hasPrefix("\(teamID).") {
                appendID(String(appID.dropFirst(teamID.count + 1)))
            } else if let dot = appID.firstIndex(of: ".") {
                appendID(String(appID[appID.index(after: dot)...]))
            }
        }
        return ids
    }

    private static func candidateSideStoreDatabaseURLs(profile: ParsedProvisioningProfile?) -> [URL] {
        var groupDirs: [URL] = []
        func appendGroupDir(_ url: URL) {
            if !groupDirs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                groupDirs.append(url)
            }
        }

        if let cls = NSClassFromString("LCSharedUtils") as? NSObject.Type {
            let selector = NSSelectorFromString("appGroupPath")
            if cls.responds(to: selector),
               let value = cls.perform(selector)?.takeUnretainedValue() {
                if let url = value as? URL {
                    appendGroupDir(url)
                } else if let path = value as? String, !path.isEmpty {
                    appendGroupDir(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        }

        let lcGroupSelector = NSSelectorFromString("lcAppGroupPath")
        if UserDefaults.responds(to: lcGroupSelector),
           let value = UserDefaults.perform(lcGroupSelector)?.takeUnretainedValue() {
            if let url = value as? URL {
                appendGroupDir(url)
            } else if let path = value as? String, !path.isEmpty {
                appendGroupDir(URL(fileURLWithPath: path, isDirectory: true))
            }
        }

        var groupIdentifiers = profile?.appGroups ?? []
        if let hostAltGroups = liveContainerHostBundle()?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            for group in hostAltGroups where !group.isEmpty && !groupIdentifiers.contains(group) {
                groupIdentifiers.append(group)
            }
        }
        for groupID in groupIdentifiers {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                appendGroupDir(url)
            }
        }

        var dbURLs: [URL] = []
        let relativePaths = [
            "Database/AltStore.sqlite",
            "SideStore/Database/AltStore.sqlite",
            "Documents/Database/AltStore.sqlite"
        ]
        for dir in groupDirs {
            for rel in relativePaths {
                let candidate = dir.appendingPathComponent(rel)
                if FileManager.default.isReadableFile(atPath: candidate.path),
                   !dbURLs.contains(where: { $0.standardizedFileURL == candidate.standardizedFileURL }) {
                    dbURLs.append(candidate)
                }
            }
        }

        if let lcHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"], !lcHome.isEmpty {
            let homeURL = URL(fileURLWithPath: lcHome, isDirectory: true)
            for rel in ["Documents/SideStore/Database/AltStore.sqlite", "Library/Application Support/SideStore/Database/AltStore.sqlite"] {
                let candidate = homeURL.appendingPathComponent(rel)
                if FileManager.default.isReadableFile(atPath: candidate.path),
                   !dbURLs.contains(where: { $0.standardizedFileURL == candidate.standardizedFileURL }) {
                    dbURLs.append(candidate)
                }
            }
        }
        return dbURLs
    }

    private static func querySideStoreExpirationDate(at dbURL: URL, bundleIdentifiers: [String]) -> Date? {
        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, openFlags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        var columns: Set<String> = []
        var pragmaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(ZINSTALLEDAPP);", -1, &pragmaStmt, nil) == SQLITE_OK,
           let pragmaStmt {
            defer { sqlite3_finalize(pragmaStmt) }
            while sqlite3_step(pragmaStmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(pragmaStmt, 1) {
                    columns.insert(String(cString: cName).uppercased())
                }
            }
        }
        guard columns.contains("ZEXPIRATIONDATE") else { return nil }

        let idColumns = ["ZRESIGNEDBUNDLEIDENTIFIER", "ZBUNDLEIDENTIFIER"].filter { columns.contains($0) }
        guard !idColumns.isEmpty else { return nil }

        let placeholders = Array(repeating: "?", count: bundleIdentifiers.count).joined(separator: ", ")
        let idPredicates = idColumns.map { "\($0) IN (\(placeholders))" }.joined(separator: " OR ")
        let activeClause = columns.contains("ZISACTIVE") ? "ZISACTIVE = 1 AND " : ""
        let sql = "SELECT MAX(ZEXPIRATIONDATE) FROM ZINSTALLEDAPP WHERE \(activeClause)(\(idPredicates));"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var bindIndex: Int32 = 1
        for _ in idColumns {
            for bundleID in bundleIdentifiers {
                sqlite3_bind_text(stmt, bindIndex, bundleID, -1, transient)
                bindIndex += 1
            }
        }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }
        let timestamp = sqlite3_column_double(stmt, 0)
        guard timestamp.isFinite else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        // Sanity check: Core Data timestamps between 2020 and 2100.
        guard date.timeIntervalSince1970 > 1_577_836_800,
              date.timeIntervalSince1970 < 4_102_444_800 else {
            return nil
        }
        return date
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return goFlyString("settings.notObtained")
        }
    }
}

@MainActor
struct GoFlyDeviceSnapshot {
    let pairingReady: Bool?
    let pairingVerification: DeviceServiceFailure?
    let pairingVerified: Bool
    let signingExpiry: String?
    let teamID: String?
    let serviceStatus: String
    let appVersion: String
    let deviceName: String
    let deviceModel: String
    let systemName: String
    let systemVersion: String

    var pairingStatus: String {
        if GoFlyUITestOverrides.frame == "F9" { return goFlyString("settings.device.paired") }
        if pairingVerification == .pairingRejected { return goFlyString("setup.pairingImport.reimportRequired") }
        if pairingVerification == .pairingRequired { return goFlyString("setup.pairingImport.notImported") }
        if pairingVerified { return goFlyString("setup.pairingImport.verified") }
        guard let pairingReady else { return goFlyString("settings.status.unknown") }
        return goFlyString(pairingReady ? "setup.pairingImport.imported" : "setup.pairingImport.notImported")
    }

    var serviceStatusDisplay: String {
        if GoFlyUITestOverrides.frame == "F9" { return goFlyString("settings.device.serviceStarted") }
        return serviceStatus
    }

    var signingExpiryStatus: String {
        if GoFlyUITestOverrides.frame == "F9" { return "2026-11-08" }
        guard let signingExpiry else { return goFlyString("settings.notObtained") }
        guard let date = ISO8601DateFormatter().date(from: signingExpiry) else {
            return signingExpiry
        }
        return Self.signingDateFormatter.string(from: date)
    }

    var daysLeftStatus: String {
        if GoFlyUITestOverrides.frame == "F9" { return String(format: goFlyString("settings.device.daysFormat"), 7) }
        guard let signingExpiry, let date = ISO8601DateFormatter().date(from: signingExpiry) else {
            return goFlyString("settings.notObtained")
        }
        let days = Int((date.timeIntervalSinceNow / 86_400).rounded(.up))
        return String(format: goFlyString("settings.device.daysFormat"), max(0, days))
    }

    private static let signingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var teamIDStatus: String {
        teamID ?? goFlyString("settings.notObtained")
    }
}

extension VPNCheckState {
    var settingsStatusKey: String {
        switch self {
        case .unknown: return "settings.status.unknown"
        case .checking: return "settings.status.checking"
        case .reachable: return "settings.status.available"
        case .unavailable: return "settings.status.unavailable"
        case .timedOut: return "settings.status.timedOut"
        }
    }
}
