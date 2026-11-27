import Foundation
import Testing
@testable import GoFlyMacCore

/// Saved IPA, GitHub Release and chooser behaviour (MAC-INSTALLER-SPEC §5.5).
private actor IpaChecker: MacChecking {
    var saved: [String: Any]?
    let installed: Bool
    let installedVersion: String
    let installedBuild: String
    let release: [String: Any]?
    let importFailure: String?
    private(set) var requests: [[String: String]] = []

    init(saved: [String: Any]?, installed: Bool, installedVersion: String = "1.0.14", installedBuild: String = "3",
         release: [String: Any]? = nil, importFailure: String? = nil) {
        self.saved = saved; self.installed = installed; self.installedVersion = installedVersion
        self.installedBuild = installedBuild; self.release = release; self.importFailure = importFailure
    }

    func check(_ request: CheckRequest) async throws -> Data {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any] ?? [:]
        requests.append(encoded.compactMapValues { $0 as? String })
        let payload: [String: Any]
        switch request.action {
        case .environment:
            payload = ["ready": true, "checks": [],
                       "teams": [["teamID": "ABCDE12345", "teamName": "Test", "isFreeProvisioningTeam": true]],
                       "ipa": saved ?? NSNull()]
        case .devices:
            payload = ["devices": [["id": "device-a", "name": "iPhone", "transport": "usb"]]]
        case .inspect:
            payload = ["device": ["id": "device-a", "name": "iPhone", "transport": "usb"],
                       "developerMode": true, "installed": installed, "vpnInstalled": true,
                       "appVersion": installed ? installedVersion : NSNull(),
                       "appBuild": installed ? installedBuild : NSNull(), "teamID": "ABCDE12345"]
        case .registeredDevices:
            payload = ["devices": []]
        case .ipaRelease:
            guard let release else { throw CheckFailure.service("release-unavailable") }
            payload = release
        case .ipaImport:
            if let importFailure { throw CheckFailure.service(importFailure) }
            saved = ["version": "1.0.15", "build": "1", "macProtocol": 1, "supported": true]
            payload = saved!
        }
        return try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "status": "ok", "payload": payload])
    }
}

nonisolated(unsafe) private let latest: [String: Any] = [
    "version": "1.0.15", "build": "1", "macProtocol": 1, "supported": true,
    "ipaURL": "https://github.com/nevenhsu/GoFly-GPS/releases/download/v1.0.15/GoFly-GPS-1.0.15.ipa",
    "sigURL": "https://github.com/nevenhsu/GoFly-GPS/releases/download/v1.0.15/GoFly-GPS-1.0.15.ipa.sig",
    "fileName": "GoFly-GPS-1.0.15.ipa", "publishedAt": "2026-12-03T00:00:00Z",
]

@MainActor private func model(_ checker: IpaChecker) async throws -> MacAppModel {
    let suite = "gofly.tests.ipa.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    let model = MacAppModel(live: checker, preferences: preferences)
    model.checkEnvironment()
    try await idle(model)
    model.openDevices(firstInstall: true)
    try await idle(model)
    model.select("device-a", transport: .usb)
    model.inspectSelected()
    try await idle(model)
    return model
}

@MainActor private func idle(_ model: MacAppModel) async throws {
    for _ in 0..<400 {
        if !model.busy && !model.isChecking && model.releaseLookup != .loading { return }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@Test func versionOrderComparesMarketingVersionBeforeBuild() {
    #expect(GoFlyVersionOrder.isNewer(version: "1.0.15", build: "1", than: "1.0.14", "3") == true)
    #expect(GoFlyVersionOrder.isNewer(version: "1.0.14", build: "3", than: "1.0.14", "3") == false)
    #expect(GoFlyVersionOrder.isNewer(version: "1.0.14", build: "2", than: "1.0.14", "3") == false)
    #expect(GoFlyVersionOrder.isNewer(version: "1.1", build: "1", than: "1.0.99", "9") == true)
    #expect(GoFlyVersionOrder.isNewer(version: nil, build: "1", than: "1.0", "1") == nil)
}

@Test func ipaRequestsEncodeOnlyTheirOwnFields() throws {
    let url = CheckRequest.ipaImport(.url(ipa: "https://example.com/a.ipa", sig: nil),
                                     minimum: (version: "1.0.14", build: "3"))
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(url)) as? [String: Any])
    #expect(Set(object.keys) == ["requestID", "action", "ipaURL", "minimumVersion", "minimumBuild"])
    let file = CheckRequest.ipaImport(.file(ipa: "/tmp/a.ipa", sig: "https://example.com/a.ipa.sig"))
    let fileObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
    #expect(Set(fileObject.keys) == ["requestID", "action", "ipaPath", "sigURL"])
    let release = CheckRequest.ipaRelease(version: "1.0.15")
    let releaseObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as? [String: Any])
    #expect(Set(releaseObject.keys) == ["requestID", "action", "version"])
}

@Test @MainActor func noSavedIpaShowsChooserWithLatestReleaseFilledIn() async throws {
    let m = try await model(IpaChecker(saved: nil, installed: false, release: latest))
    #expect(m.devicePageState == .chooseIpa)
    m.loadLatestRelease()
    try await idle(m)
    #expect(m.ipaURLText == latest["ipaURL"] as? String)
    #expect(m.canImportIpa)
    m.importSelectedIpa()
    try await idle(m)
    #expect(m.savedIpa?.version == "1.0.15")
    #expect(m.devicePageState == .readyToInstall)
}

@Test @MainActor func failedImportShowsD16AndKeepsNothing() async throws {
    let m = try await model(IpaChecker(saved: nil, installed: false, release: latest, importFailure: "ipa-signature-invalid"))
    m.loadLatestRelease()
    try await idle(m)
    m.importSelectedIpa()
    try await idle(m)
    #expect(m.ipaFailure == .service("ipa-signature-invalid"))
    #expect(m.savedIpa == nil)
    #expect(m.devicePageState == .chooseIpa)
}

@Test @MainActor func importSendsPhoneVersionAsDowngradeFloor() async throws {
    let checker = IpaChecker(saved: ["version": "1.0.14", "build": "3"], installed: true, release: latest)
    let m = try await model(checker)
    m.openIpaChooser()
    try await idle(m)
    m.importSelectedIpa()
    try await idle(m)
    let sent = await checker.requests.last { $0["action"] == "ipaImport" }
    #expect(sent?["minimumVersion"] == "1.0.14")
    #expect(sent?["minimumBuild"] == "3")
    #expect(sent?["sigURL"] == latest["sigURL"] as? String)
}

@Test @MainActor func newerGitHubReleaseShowsD17AndSameBuildShowsD08() async throws {
    let m = try await model(IpaChecker(saved: ["version": "1.0.14", "build": "3"], installed: true, release: latest))
    #expect(m.devicePageState == .installed)
    _ = await m.refreshLatestRelease()
    #expect(m.devicePageState == .releaseAvailable)
}

@Test @MainActor func savedIpaOlderThanPhoneNeverRenewsAndAsksForAnother() async throws {
    let m = try await model(IpaChecker(saved: ["version": "1.0.13", "build": "9"], installed: true))
    #expect(m.savedIpaIsOlderThanInstalled)
    #expect(m.devicePageState == .chooseIpa)
    #expect(!m.canCloseIpaChooser)
}

@Test @MainActor func fileModeNeedsBothFieldsAndFindsSiblingSignature() async throws {
    let m = try await model(IpaChecker(saved: nil, installed: false))
    m.setIpaSourceMode(.file)
    #expect(!m.canImportIpa)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let ipa = folder.appendingPathComponent("GoFly-GPS-1.0.15.ipa")
    try Data("ipa".utf8).write(to: ipa)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("GoFly-GPS-1.0.15.ipa.sig"))
    m.selectIpaFile(ipa.path)
    #expect(m.signatureOrigin == .sameFolder)
    #expect(m.signatureLocation == ipa.path + ".sig")
    #expect(m.canImportIpa)
}

/// Real Swift -> Packaged GoFly.app ProcessBridge E2E with only the iPhone simulated.
/// Run with an isolated HOME and GOFLY_E2E_PACKAGED_APP=1 so user state is never touched.
private actor SimulatedPhoneOverRealBridge: MacChecking {
    let real: ProcessBridge
    var installed = false
    var installedVersion = "1.0.14"
    var installedBuild = "5"

    init(real: ProcessBridge) { self.real = real }

    func setPhoneInstalled(_ installed: Bool, version: String = "1.0.14", build: String = "5") {
        self.installed = installed
        self.installedVersion = version
        self.installedBuild = build
    }

    func check(_ request: CheckRequest) async throws -> Data {
        switch request.action {
        case .environment, .ipaImport, .ipaRelease, .registeredDevices:
            return try await real.check(request)
        case .devices:
            let payload: [String: Any] = ["devices": [
                ["id": "00008110-0000000000000001", "name": "Simulated iPhone", "transport": "usb", "osVersion": "26.4"]
            ]]
            return try JSONSerialization.data(withJSONObject: [
                "requestID": request.requestID, "status": "ok", "payload": payload
            ])
        case .inspect:
            let payload: [String: Any] = [
                "device": ["id": "00008110-0000000000000001", "name": "Simulated iPhone", "transport": "usb", "osVersion": "26.4"],
                "developerMode": true, "installed": installed, "vpnInstalled": installed,
                "appVersion": installed ? installedVersion : NSNull(),
                "appBuild": installed ? installedBuild : NSNull(),
                "teamID": request.teamID ?? NSNull(),
            ]
            return try JSONSerialization.data(withJSONObject: [
                "requestID": request.requestID, "status": "ok", "payload": payload
            ])
        }
    }
}

@Test @MainActor func packagedAppRealBridgeEndToEndWithSimulatedPhone() async throws {
    guard ProcessInfo.processInfo.environment["GOFLY_E2E_PACKAGED_APP"] == "1" else { return }
    let workspace = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let resources = workspace.appendingPathComponent("work/gofly-mac/GoFly.app/Contents/Resources", isDirectory: true)
    let ipaDir = workspace.appendingPathComponent("work/dist/ipa", isDirectory: true)
    let ipa = try #require(
        try FileManager.default.contentsOfDirectory(at: ipaDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "ipa" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    )
    let sig = URL(fileURLWithPath: ipa.path + ".sig")
    #expect(FileManager.default.fileExists(atPath: sig.path))

    let bundle = try MacBundleResources(resourcesURL: resources)
    let realBridge = ProcessBridge(bundle: bundle)
    let journal = BridgeStatusJournalReader(runner: realBridge)
    let hybrid = SimulatedPhoneOverRealBridge(real: realBridge)

    // 1. Fresh launch with no saved IPA -> D15 (chooseIpa).
    let suite1 = "gofly.e2e.1.\(UUID().uuidString)"
    let prefs1 = try #require(UserDefaults(suiteName: suite1))
    defer { prefs1.removePersistentDomain(forName: suite1) }
    let setup1 = MacSetupModel(runner: realBridge, journal: journal)
    let m1 = MacAppModel(live: hybrid, setup: setup1, preferences: prefs1)
    await m1.restoreSetup()
    m1.beginLaunchCheck()
    try await idle(m1)
    #expect(m1.environment?.ready == true)
    #expect(m1.savedIpa == nil)
    m1.openDevices(firstInstall: true)
    try await idle(m1)
    #expect(m1.devicePageState == .chooseIpa)

    // 2. Choose local signed IPA (auto-detects sibling .sig) -> real ProcessBridge ipaImport -> D04 (readyToInstall).
    m1.setIpaSourceMode(.file)
    m1.selectIpaFile(ipa.path)
    #expect(m1.signatureOrigin == .sameFolder)
    #expect(m1.canImportIpa)
    m1.importSelectedIpa()
    try await idle(m1)
    let imported = try #require(m1.savedIpa)
    #expect(imported.supported == true)
    #expect(m1.ipaFailure == nil)
    #expect(m1.devicePageState == .readyToInstall)

    // 3. Relaunch (fresh MacAppModel) -> real ProcessBridge environment reads saved IPA -> directly D04.
    let suite2 = "gofly.e2e.2.\(UUID().uuidString)"
    let prefs2 = try #require(UserDefaults(suiteName: suite2))
    defer { prefs2.removePersistentDomain(forName: suite2) }
    let m2 = MacAppModel(live: hybrid, setup: MacSetupModel(runner: realBridge, journal: journal), preferences: prefs2)
    await m2.restoreSetup()
    m2.beginLaunchCheck()
    try await idle(m2)
    #expect(m2.savedIpa?.version == imported.version)
    #expect(m2.savedIpa?.build == imported.build)
    m2.openDevices(firstInstall: true)
    try await idle(m2)
    #expect(m2.devicePageState == .readyToInstall)

    // 4. Tampered IPA is rejected by real ProcessBridge -> D16, saved IPA preserved.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let tampered = tmp.appendingPathComponent("tampered.ipa")
    try FileManager.default.copyItem(at: ipa, to: tampered)
    let handle = try FileHandle(forWritingTo: tampered)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("x".utf8))
    try handle.close()
    m2.openIpaChooser()
    m2.setIpaSourceMode(.file)
    m2.selectIpaFile(tampered.path)
    m2.selectSignatureFile(sig.path)
    m2.importSelectedIpa()
    try await idle(m2)
    #expect(m2.ipaFailure == .service("ipa-signature-invalid"))
    #expect(m2.savedIpa?.version == imported.version)

    // 5. Downgrade below phone's installed version is rejected by real ProcessBridge.
    await hybrid.setPhoneInstalled(true, version: "99.0.0", build: "1")
    m2.closeIpaChooser()
    m2.inspectSelected()
    try await idle(m2)
    #expect(m2.savedIpaIsOlderThanInstalled)
    #expect(m2.devicePageState == .chooseIpa)
    m2.setIpaSourceMode(.file)
    m2.selectIpaFile(ipa.path)
    m2.importSelectedIpa()
    try await idle(m2)
    #expect(m2.ipaFailure == .service("ipa-downgrade"))
}
