import Foundation
import Testing
import GoFlyMacCore

private struct EchoChecker: MacChecking {
    let wrongDevice: Bool
    var installed: Bool? = nil
    var installedVersion: String? = nil
    var installedBuild: String? = nil
    var expiresAt: String? = nil
    var developerMode: Bool? = true
    var inspectFailure: CheckFailure? = nil
    func check(_ request: CheckRequest) async throws -> Data {
        let payload: [String: Any]
        switch request.action {
        case .environment: payload = ["ready": true, "checks": [
                                        ["id": "macos-version", "title": "macOS", "detail": "通過", "passed": true],
                                        ["id": "available-space", "title": "可用空間", "detail": "通過", "passed": true],
                                        ["id": "xcode-installed", "title": "Xcode", "detail": "通過", "passed": true],
                                        ["id": "xcode-first-launch", "title": "Xcode 元件", "detail": "通過", "passed": true],
                                        ["id": "ios-platform", "title": "iOS 平台", "detail": "通過", "passed": true],
                                        ["id": "apple-account", "title": "Apple 帳號", "detail": "通過", "passed": true]],
                                     "teams": [["teamID": "ABCDE12345", "teamName": "Test Team", "isFreeProvisioningTeam": true]],
                                     "xcodeVersion": "27.1", "projectVersion": "0.2.0", "projectBuild": "21"]
        case .devices: payload = ["devices": [["id": "device-a", "name": "iPhone", "transport": "usb"],
                                              ["id": "device-a", "name": "iPhone", "transport": "wifi"]]]
        case .inspect:
            if let inspectFailure { throw inspectFailure }
            payload = ["device": ["id": wrongDevice ? "device-b" : "device-a", "name": "iPhone", "transport": request.transport?.rawValue ?? "usb"],
                       "developerMode": developerMode.map { $0 as Any } ?? NSNull(), "installed": installed.map { $0 as Any } ?? NSNull(),
                       "vpnInstalled": NSNull(),
                       "appVersion": installedVersion.map { $0 as Any } ?? NSNull(),
                       "appBuild": installedBuild.map { $0 as Any } ?? NSNull(),
                       "expiresAt": expiresAt.map { $0 as Any } ?? NSNull()]
        case .registeredDevices:
            #expect(request.teamID == "ABCDE12345")
            payload = ["devices": [["id": "device-a", "name": ""], ["id": "device-z", "name": "Old iPhone"]]]
        }
        return try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
                                                           "status": "ok", "payload": payload])
    }
}

private struct SlowChecker: MacChecking {
    func check(_ request: CheckRequest) async throws -> Data {
        // Deliberately ignore cancellation to model a late child-process response.
        try? await Task.sleep(for: .milliseconds(120))
        return try await EchoChecker(wrongDevice: false).check(request)
    }
}

private struct RouteChecker: MacChecking {
    let failingID: String?
    var error: CheckFailure? = nil
    func check(_ request: CheckRequest) async throws -> Data {
        if let error { throw error }
        let checks = routeChecks(failingID)
        let payload: [String: Any] = request.action == .environment
            ? ["ready": checks.allSatisfy { $0["passed"] as? Bool == true },
               "checks": checks,
               "teams": [["teamID": "ABCDE12345", "teamName": "Test Team", "isFreeProvisioningTeam": true]],
               "xcodeVersion": "27.1"]
            : ["devices": []]
        return try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID, "status": "ok", "payload": payload,
        ])
    }
}

private actor MutableRouteChecker: MacChecking {
    private var failingID: String?
    private let teamCount: Int

    init(failingID: String?, teamCount: Int = 1) {
        self.failingID = failingID
        self.teamCount = teamCount
    }

    func setFailingID(_ id: String?) { failingID = id }

    func check(_ request: CheckRequest) async throws -> Data {
        let checks = routeChecks(failingID)
        let teams = (0..<teamCount).map { index in
            ["teamID": "TEAM\(index)", "teamName": "Team \(index + 1)",
             "isFreeProvisioningTeam": index == 0] as [String: Any]
        }
        let payload: [String: Any] = request.action == .environment
            ? ["ready": checks.allSatisfy { $0["passed"] as? Bool == true },
               "checks": checks, "teams": teams, "xcodeVersion": "27.1"]
            : ["devices": []]
        return try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID, "status": "ok", "payload": payload,
        ])
    }
}

private func routeChecks(_ failingID: String? = nil) -> [[String: Any]] {
    ["macos-version", "available-space", "xcode-installed", "xcode-first-launch", "ios-platform", "apple-account"]
        .map { id in ["id": id, "title": id, "detail": "狀態", "passed": failingID.map { id != $0 } ?? true] }
}

private actor HeldChecker: MacChecking {
    private var pending: [(CheckRequest, CheckedContinuation<Data, Error>)] = []
    func check(_ request: CheckRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { pending.append((request, $0)) }
    }
    func entered() -> Bool { !pending.isEmpty }
    func finish() async throws {
        let commands = pending
        pending = []
        for (request, pendingTransaction) in commands {
            pendingTransaction.resume(returning: try await EchoChecker(wrongDevice: false).check(request))
        }
    }
}

@MainActor private func settled(_ model: MacAppModel) async throws {
    for _ in 0..<200 {
        if !model.busy { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Model did not finish the check")
}

@Test func readOnlyActionSet() {
    #expect(CheckAction(rawValue: "install") == nil)
    #expect(CheckAction(rawValue: "repair") == nil)
    #expect(CheckAction(rawValue: "reinstall") == nil)
}

@Test @MainActor func firstOpenFlagIsRecordedInLocalPreferences() throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }

    let first = MacAppModel(live: EchoChecker(wrongDevice: false), preferences: preferences)
    let next = MacAppModel(live: EchoChecker(wrongDevice: false), preferences: preferences)
    #expect(first.isFirstOpen)
    #expect(!next.isFirstOpen)
}

@Test @MainActor func startupRoutesReadyMacToDeviceList() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: RouteChecker(failingID: nil), preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .deviceList)
    #expect(model.selectedTeam?.teamID == "ABCDE12345")
}

@Test @MainActor func firstOpenWithoutXcodeRoutesToOverview() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: RouteChecker(failingID: "xcode-installed"), preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.isFirstOpen)
    #expect(model.route == .environment(.overview))
}

@Test @MainActor func overviewStartsAtFirstIncompleteEnvironmentStep() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: RouteChecker(failingID: "xcode-installed"), preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .environment(.overview))
    #expect(model.canBeginEnvironmentPreparation)
    model.startEnvironmentPreparation()
    #expect(model.route == .environment(.getXcode))
}

@Test @MainActor func overviewDoesNotContinueWhenRequiredStorageIsUnavailable() async throws {
    let model = MacAppModel(live: RouteChecker(failingID: "available-space"))
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .environment(.overview))
    #expect(!model.canBeginEnvironmentPreparation)
}

@Test @MainActor func environmentStepAdvancesWhenRecheckPassesAndXcodeWaitIsStable() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    preferences.set(true, forKey: "gofly.mac.hasOpenedBefore")
    defer { preferences.removePersistentDomain(forName: suite) }
    let checker = MutableRouteChecker(failingID: "xcode-installed")
    let model = MacAppModel(live: checker, preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .environment(.getXcode))

    model.waitForXcodeInstall()
    model.checkEnvironment()
    try await settled(model)
    #expect(model.route == .environment(.waitForXcode))

    await checker.setFailingID("xcode-first-launch")
    model.checkEnvironment()
    try await settled(model)
    #expect(model.route == .environment(.firstLaunch))

    await checker.setFailingID("ios-platform")
    model.checkEnvironment()
    try await settled(model)
    #expect(model.route == .environment(.iosPlatform))
}

@Test @MainActor func selectingTeamWaitsForExplicitUseAction() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: MutableRouteChecker(failingID: nil, teamCount: 2), preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .environment(.selectTeam))
    model.selectTeam("TEAM0")
    model.checkEnvironment()
    try await settled(model)
    #expect(model.route == .environment(.selectTeam))
    model.returnToDevices()
    #expect(model.route == .deviceList)
}

@Test @MainActor func returningMacRoutesToFirstIncompleteStep() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    preferences.set(true, forKey: "gofly.mac.hasOpenedBefore")
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: RouteChecker(failingID: "ios-platform"), preferences: preferences)
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .environment(.iosPlatform))
}

@Test @MainActor func startupCheckFailureStaysOnLaunchRoute() async throws {
    let model = MacAppModel(live: RouteChecker(failingID: nil, error: .timeout))
    model.beginLaunchCheck()
    try await settled(model)
    #expect(model.route == .startup)
    #expect(model.failure == .timeout)
}

@Test func dedupPrefersUSBAndFirstInstallExcludesWiFi() {
    let wifi = ConnectedDevice(id: "ABC", name: "Phone", transport: .wifi)
    let usb = ConnectedDevice(id: "abc", name: "Phone", transport: .usb)
    let other = ConnectedDevice(id: "other", name: "Other", transport: .wifi)
    let management = ConnectedDevice.unique([wifi, usb, other], usbOnly: false)
    #expect(management.count == 2)
    #expect(management.first(where: { $0.id.lowercased() == "abc" })?.transport == .usb)
    #expect(ConnectedDevice.unique([wifi, usb, other], usbOnly: true) == [usb])
    let choices = ConnectedDevice.connectionChoices([wifi, usb, wifi, other], usbOnly: false)
    #expect(choices.count == 3)
    #expect(Set(choices.map(\.connectionID)).count == 3)
    #expect(ConnectedDevice.connectionChoices([wifi, usb, other], usbOnly: true) == [usb])
}

@Test func connectedDeviceModelNameIsOptionalAndDecodesWhenPresent() throws {
    let withModel = Data(#"{"id":"device","name":"Neven 的 iPhone","modelName":"iPhone16,1","transport":"usb","osVersion":"27.0"}"#.utf8)
    let withoutModel = Data(#"{"id":"device","name":"Neven 的 iPhone","transport":"usb","osVersion":"27.0"}"#.utf8)
    #expect(try JSONDecoder().decode(ConnectedDevice.self, from: withModel).modelName == "iPhone16,1")
    #expect(try JSONDecoder().decode(ConnectedDevice.self, from: withoutModel).modelName == nil)
}

@Test func responseMustMatchFreshRequest() throws {
    let pinned = CheckRequest(action: .inspect, deviceID: "abc", transport: .wifi)
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pinned)) as? [String: Any])
    #expect(encoded["transport"] as? String == "wifi")
    let request = CheckRequest(action: .environment)
    let oldRequest = CheckRequest(action: .environment)
    let stale = try JSONSerialization.data(withJSONObject: ["requestID": oldRequest.requestID,
        "status": "ok", "payload": ["ready": true, "checks": []]])
    #expect(throws: CheckFailure.invalidResponse) {
        try ResponseDecoder.decode(stale, for: request, as: MacEnvironment.self)
    }
}

@Test func malformedOversizeAndMultipleResponsesFail() {
    let request = CheckRequest(action: .environment)
    for data in [Data(), Data(repeating: 65, count: 262_145), Data("{}{}".utf8), Data("not-json".utf8)] {
        #expect(throws: CheckFailure.invalidResponse) {
            try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
        }
    }
}

@Test func environmentKeepsUnknownStateWithoutTreatingItAsPassed() throws {
    let request = CheckRequest(action: .environment)
    let data = try JSONSerialization.data(withJSONObject: [
        "requestID": request.requestID,
        "status": "ok",
        "payload": [
            "ready": false,
            "checks": [["id": "ios-platform", "title": "iOS 平台", "detail": "無法確認", "status": "unknown", "passed": false]],
            "teams": [],
        ],
    ])
    let environment = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
    #expect(environment.checks.first?.status == .unknown)
    #expect(environment.checks.first?.passed == false)
}

@Test func unknownErrorCannotLeakArbitraryDiagnostics() throws {
    let request = CheckRequest(action: .devices)
    let data = try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
        "status": "error", "code": "sensitive raw device output"])
    #expect(throws: CheckFailure.invalidResponse) {
        try ResponseDecoder.decode(data, for: request, as: DeviceList.self)
    }
}

@Test @MainActor func environmentGateAndIdentityMismatch() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: true))
    model.navigate(.deviceList)
    #expect(model.route == .environment(.overview))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: true); try await settled(model)
    model.select("device-a")
    model.inspectSelected(); try await settled(model)
    #expect(model.inspection == nil)
    #expect(model.failure == .invalidResponse)
    #expect(model.route == .deviceDetail)
}

@Test @MainActor func installedPhoneOnFirstInstallOffersDevicePage() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: true); try await settled(model)
    model.select("device-a", transport: .usb)
    model.inspectSelected(); try await settled(model)
    #expect(model.installedOnFirstInstall)
    #expect(model.devicePageState == .installed)
    #expect(model.route == .deviceDetail)
    model.openSelectedDevicePage()
    #expect(!model.firstInstall)
    #expect(model.route == .deviceDetail)
    #expect(model.selectedID == "device-a")
    #expect(model.selectedTransport == .usb)
}

@Test @MainActor func deviceManagementChoosesUpdateOrRenew() async throws {
    let update = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true,
                                               installedVersion: "0.1.0", installedBuild: "20"))
    update.checkEnvironment(); try await settled(update)
    update.openDevices(firstInstall: false); try await settled(update)
    update.select("device-a", transport: .usb)
    update.inspectSelected(); try await settled(update)
    #expect(update.route == .deviceDetail)
    #expect(update.renewButtonTitle == "更新 GoFly")

    let renew = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true,
                                              installedVersion: "0.2.0", installedBuild: "21"))
    renew.checkEnvironment(); try await settled(renew)
    renew.openDevices(firstInstall: false); try await settled(renew)
    renew.select("device-a", transport: .usb)
    renew.inspectSelected(); try await settled(renew)
    #expect(renew.renewButtonTitle == "延長簽名期限")
}

@Test @MainActor func inspectionResultsChooseDevicePagesWithoutStartingWrites() async throws {
    func inspect(_ checker: EchoChecker, transport: ConnectedDevice.Transport = .usb) async throws -> MacAppModel {
        let model = MacAppModel(live: checker)
        model.checkEnvironment(); try await settled(model)
        model.openDevices(firstInstall: false); try await settled(model)
        model.select("device-a", transport: transport)
        model.inspectSelected(); try await settled(model)
        return model
    }

    let trust = try await inspect(EchoChecker(wrongDevice: false, inspectFailure: .service("trust-required")))
    #expect(trust.devicePageState == .trustRequired)

    let developerMode = try await inspect(EchoChecker(wrongDevice: false, installed: false, developerMode: false))
    #expect(developerMode.devicePageState == .developerModeRequired)

    let installReady = try await inspect(EchoChecker(wrongDevice: false, installed: false))
    #expect(installReady.devicePageState == .readyToInstall)

    let installed = try await inspect(EchoChecker(wrongDevice: false, installed: true,
                                                  installedVersion: "0.2.0", installedBuild: "21"))
    #expect(installed.devicePageState == .installed)

    let update = try await inspect(EchoChecker(wrongDevice: false, installed: true,
                                               installedVersion: "0.1.0", installedBuild: "20"))
    #expect(update.devicePageState == .updateAvailable)

    let usbRequired = try await inspect(EchoChecker(wrongDevice: false, installed: false), transport: .wifi)
    #expect(usbRequired.devicePageState == .wifiNeedsUSB)

    let wifiUnavailable = try await inspect(EchoChecker(wrongDevice: false,
                                                        inspectFailure: .service("device-disconnected")), transport: .wifi)
    #expect(wifiUnavailable.devicePageState == .wifiUnavailable)
}

@Test @MainActor func autoRenewPreferenceDefaultsOnAndPersistsLocally() throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let first = MacAppModel(live: RouteChecker(failingID: nil), preferences: preferences)
    #expect(first.autoRenewEnabled)
    first.setAutoRenewEnabled(false)
    let reopened = MacAppModel(live: RouteChecker(failingID: nil), preferences: preferences)
    #expect(!reopened.autoRenewEnabled)
}

@Test @MainActor func autoRenewPreferenceIsScopedToEachPhone() throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: RouteChecker(failingID: nil), preferences: preferences)
    let first = ConnectedDevice(id: "00008110-001234567890abcd", name: "First", transport: .usb)
    let second = ConnectedDevice(id: "00008110-009876543210abcd", name: "Second", transport: .wifi)
    #expect(model.autoRenewEnabled(for: first))
    #expect(model.autoRenewEnabled(for: second))
    model.setAutoRenewEnabled(false, for: first)
    #expect(!model.autoRenewEnabled(for: first))
    #expect(model.autoRenewEnabled(for: second))
}

@Test func autoRenewPolicyUsesFourDayBoundaryAndTwentyFourHourCadence() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(MacAutoRenewPolicy.isCheckDue(now: now, lastCheck: nil))
    #expect(!MacAutoRenewPolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-86_399)))
    #expect(MacAutoRenewPolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-86_400)))

    #expect(!MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(4 * 86_400),
                                            enabled: true, installed: true, reachable: true,
                                            networkAvailable: true, operationInProgress: false))
    #expect(MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(4 * 86_400 - 1),
                                           enabled: true, installed: true, reachable: true,
                                           networkAvailable: true, operationInProgress: false))
    #expect(MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(-1),
                                           enabled: true, installed: true, reachable: true,
                                           networkAvailable: true, operationInProgress: false))
    #expect(!MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(1),
                                            enabled: false, installed: true, reachable: true,
                                            networkAvailable: true, operationInProgress: false))
    #expect(!MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(1),
                                            enabled: true, installed: true, reachable: true,
                                            networkAvailable: true, operationInProgress: true))
    #expect(!MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(1),
                                            enabled: true, installed: true, reachable: true,
                                            networkAvailable: false, operationInProgress: false))
    #expect(!MacAutoRenewPolicy.shouldBegin(now: now, expiresAt: now.addingTimeInterval(1),
                                            enabled: true, installed: true, reachable: false,
                                            networkAvailable: true, operationInProgress: false))
}

@Test @MainActor func cancellationDiscardsLateResult() async throws {
    let model = MacAppModel(live: SlowChecker())
    model.checkEnvironment()
    model.cancel()
    try await Task.sleep(for: .milliseconds(180))
    #expect(model.environment == nil)
    #expect(!model.busy)
}

@Test @MainActor func cancelledReadOnlyCheckRetainsAdmissionUntilItReturns() async throws {
    let runner = HeldChecker()
    let model = MacAppModel(live: runner)
    model.checkEnvironment()
    for _ in 0..<200 {
        if await runner.entered() { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await runner.entered())
    model.cancel()
    #expect(model.busy)
    model.navigate(.environment(.overview))
    #expect(model.route == .startup, "A pending read-only check keeps its current startup route until it returns.")
    try await runner.finish()
    try await settled(model)
    #expect(!model.busy)
    #expect(model.environment == nil)
}

@Test @MainActor func wifiRescanRetainsSelectionAndReinspectsWhenFound() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: false))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: false); try await settled(model)
    #expect(model.visibleDevices.count == 1)
    #expect(model.availableConnections.count == 2)
    model.select("device-a"); model.inspectSelected(); try await settled(model)
    #expect(model.inspection != nil)
    #expect(model.inspection?.installed == nil)
    model.inspectSelected(); try await settled(model)
    model.select("device-a", transport: .wifi)
    #expect(model.inspection == nil)
    model.inspectSelected(); try await settled(model)
    #expect(model.inspection?.device.transport == .wifi)
    model.refreshDevices(); try await settled(model)
    #expect(model.inspection?.device.transport == .wifi)
    #expect(model.selectedID == "device-a")
}

@Test func boundedProcessStopsOnTimeout() throws {
    let runner = BoundedProcess()
    #expect(throws: CheckFailure.timeout) {
        try runner.run(executable: "/usr/bin/python3", arguments: ["-c", "import os,time; os.setpgrp(); time.sleep(10)"],
                       developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 0.15)
    }
}

@Test func boundedProcessRejectsOversizeAndCrash() throws {
    let runner = BoundedProcess()
    #expect(throws: CheckFailure.invalidResponse) {
        try runner.run(executable: "/usr/bin/python3", arguments: ["-c", "import os; os.setpgrp(); print('x'*300000)"],
                       developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 5)
    }
    let crashing = BoundedProcess()
    #expect(throws: CheckFailure.invalidResponse) {
        try crashing.run(executable: "/usr/bin/python3", arguments: ["-c", "raise RuntimeError('private diagnostic')"],
                         developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 5)
    }
}

@Test @MainActor func registeredPhonesUseRememberedNamesWhenXcodeHasNone() async throws {
    let suite = "gofly.tests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = MacAppModel(live: EchoChecker(wrongDevice: false, installed: false), preferences: preferences)
    model.checkEnvironment()
    try await settled(model)
    model.refreshDevices()
    try await settled(model)
    #expect(model.inspection?.device.name == "iPhone")
    model.loadRegisteredDevices()
    for _ in 0..<200 where model.registeredDevices == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(model.registeredDevices == [RegisteredDevice(id: "device-a", name: "iPhone"),
                                        RegisteredDevice(id: "device-z", name: "Old iPhone")])
}
