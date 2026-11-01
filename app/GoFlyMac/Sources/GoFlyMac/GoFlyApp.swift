import AppKit
import SwiftUI
import GoFlyMacCore

@main
struct GoFlyApp: App {
    @State private var model: MacAppModel
    @State private var autoRenewRuntime = MacAutoRenewRuntime()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let captureColorScheme: ColorScheme?

    init() {
        let checker: any MacChecking
        let setupRunner: any MacSetupRunning
        let setupJournal: any MacSetupJournalReading
        #if DEBUG
        let bundleID = Bundle.main.bundleIdentifier
        let captureBundle = bundleID?.hasPrefix("com.neven.gofly.capture") == true
        if CaptureLaunchOptions.isEnabled || captureBundle {
            let journal = CaptureSetupJournal(screen: CaptureLaunchOptions.screen)
            checker = CaptureChecker()
            setupRunner = CaptureSetupRunner(journal: journal)
            setupJournal = journal
        } else {
            (checker, setupRunner, setupJournal) = Self.liveServices()
        }
        captureColorScheme = CaptureLaunchOptions.colorScheme
            ?? (bundleID?.contains("light") == true ? .light : captureBundle ? .dark : nil)
        #else
        (checker, setupRunner, setupJournal) = Self.liveServices()
        captureColorScheme = nil
        #endif
        let setup = MacSetupModel(runner: setupRunner, journal: setupJournal)
        #if DEBUG
        let preferences: UserDefaults
        if let suite = CaptureLaunchOptions.preferencesSuiteName,
           let capturePreferences = UserDefaults(suiteName: suite) {
            preferences = capturePreferences
        } else if let bundleID = Bundle.main.bundleIdentifier,
           bundleID.hasPrefix("com.neven.gofly.capture"),
           let suite = UserDefaults(suiteName: bundleID) {
            preferences = suite
        } else {
            preferences = .standard
        }
        #else
        let preferences = UserDefaults.standard
        #endif
        _model = State(initialValue: MacAppModel(live: checker, setup: setup, preferences: preferences))
    }

    private static func liveServices() -> (any MacChecking, any MacSetupRunning, any MacSetupJournalReading) {
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        do {
            let bundle = try MacBundleResources(resourcesURL: resources)
            let bridge = ProcessBridge(bundle: bundle)
            return (bridge, bridge, BridgeStatusJournalReader(runner: bridge))
        } catch {
            let unavailable = UnavailableChecker(reason: (error as? CheckFailure) ?? .unavailable)
            return (unavailable, unavailable, EmptySetupJournal())
        }
    }

    var body: some Scene {
        Window("", id: "main") {
            MacRootView(model: model)
                .preferredColorScheme(captureColorScheme)
                .frame(minWidth: 1000, minHeight: 700)
                .onChange(of: model.setup?.autoRenewState) { _, state in
                    #if DEBUG
                    if !CaptureLaunchOptions.isEnabled, let state { autoRenewRuntime.handle(state) }
                    #else
                    if let state { autoRenewRuntime.handle(state) }
                    #endif
                }
                .task {
                    await model.restoreSetup()
                    model.beginLaunchCheck()
                    #if DEBUG
                    if !CaptureLaunchOptions.isEnabled {
                        autoRenewRuntime.start(model: model)
                    }
                    #else
                    autoRenewRuntime.start(model: model)
                    #endif
                    #if DEBUG
                    if let screen = CaptureLaunchOptions.screen {
                        Task { @MainActor in
                            for _ in 0..<200 {
                                if model.hasCheckedEnvironment && !model.isChecking { break }
                                try? await Task.sleep(for: .milliseconds(50))
                            }
                            guard model.hasCheckedEnvironment, !model.isChecking else { return }
                            switch screen {
                            case "D14":
                                model.prepareD14Capture(
                                    usbDevice: ConnectedDevice(id: "00008110-0000000000000006", name: "Neven 的 iPhone",
                                                               transport: .usb, osVersion: "27.0.1", modelName: "iPhone 15 Pro"),
                                    wifiDevice: ConnectedDevice(id: "00008110-0000000000000014", name: "測試 iPhone",
                                                                transport: .wifi, osVersion: "27.0.1", modelName: "iPhone 14")
                                )
                            case "D01":
                                model.openDevices(firstInstall: true)
                            case "D02", "D03", "D04":
                                model.openDevices(firstInstall: true)
                            case "D05", "D06", "D07":
                                model.openDevices(firstInstall: true)
                                for _ in 0..<200 {
                                    if model.route == .deviceDetail && !model.busy { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                model.beginFirstInstall()
                                for _ in 0..<240 {
                                    if model.setup?.canApply == true { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                if model.setup?.canApply == true { model.setup?.apply() }
                                let targetStage: MacSetupStage = screen == "D05" ? .artifact : .handoff
                                for _ in 0..<200 {
                                    if screen == "D07", model.setup?.snapshot?.isComplete == true { break }
                                    if screen != "D07", model.setup?.progressStage == targetStage { break }
                                    try? await Task.sleep(for: .milliseconds(50))
                                }
                            case "D08", "D09", "D12", "D13":
                                model.openDevices(firstInstall: false)
                                for _ in 0..<200 {
                                    if !model.isChecking { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                if ["D08", "D12", "D13"].contains(screen) {
                                    model.select("capture-secondary", transport: .usb)
                                    model.inspectSelected()
                                    for _ in 0..<200 {
                                        if !model.busy { break }
                                        try? await Task.sleep(for: .milliseconds(25))
                                    }
                                }
                                let transport: ConnectedDevice.Transport = screen == "D08" || screen == "D12" || screen == "D13" ? .wifi : .usb
                                model.select("capture-device", transport: transport)
                                model.inspectSelected()
                            case "E01": model.navigate(.environment(.overview))
                            case "E02": model.navigate(.environment(.updateMacOS))
                            case "E03": model.navigate(.environment(.getXcode))
                            case "E04": model.navigate(.environment(.waitForXcode))
                            case "E05": model.navigate(.environment(.firstLaunch))
                            case "E06": model.navigate(.environment(.iosPlatform))
                            case "E07": model.navigate(.environment(.appleAccount))
                            case "E08": model.navigate(.environment(.selectTeam))
                            case "E09": model.navigate(.environmentSummary)
                            default: break
                            }
                            if screen == "E09" {
                                model.refreshDevices()
                                for _ in 0..<100 {
                                    if !model.isChecking { break }
                                    try? await Task.sleep(for: .milliseconds(50))
                                }
                            }
                            if ["D02", "D03", "D04", "D08", "D09", "D12", "D13"].contains(screen) {
                                for _ in 0..<200 {
                                    if model.route == .deviceDetail && !model.busy { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                if screen == "D13" {
                                    model.refreshDevices()
                                    for _ in 0..<200 {
                                        if !model.busy { break }
                                        try? await Task.sleep(for: .milliseconds(25))
                                    }
                                }
                            }
                            if screen == "D10" || screen == "D11" {
                                model.openDevices(firstInstall: false)
                                for _ in 0..<200 {
                                    if !model.isChecking { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                model.select("00008110-0000000000000014", transport: .wifi)
                                model.inspectSelected()
                                for _ in 0..<200 {
                                    if !model.busy { break }
                                    try? await Task.sleep(for: .milliseconds(25))
                                }
                                model.setNetworkAvailable(true)
                                await model.checkAutomaticRenewal(now: Date())
                                for _ in 0..<200 {
                                    if model.setup?.autoRenewState == .running || model.setup?.autoRenewState == .completed { break }
                                    try? await Task.sleep(for: .milliseconds(50))
                                }
                            }
                        }
                    }
                    if Bundle.main.infoDictionary?["GoFlyCaptureScreen"] as? String == "D01" {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(900))
                            model.openDevices(firstInstall: true)
                            try? await Task.sleep(for: .milliseconds(350))
                            await CaptureScreenshotHelper.captureIfRequested(expectedScreen: "D01")
                        }
                    }
                    #endif
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct EmptySetupJournal: MacSetupJournalReading {
    func readPendingTransaction() async throws -> MacSetupTransactionIdentity? { nil }
    func readState() async throws -> MacSetupJournalState {
        MacSetupJournalState(pendingTransaction: nil, completed: nil)
    }
}

#if DEBUG
enum CaptureLaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments
    static var isEnabled: Bool { arguments.contains("--ui-capture") }
    static var screen: String? {
        arguments.first(where: { $0.hasPrefix("--capture-screen=") })?
            .replacingOccurrences(of: "--capture-screen=", with: "")
    }
    private static var appearance: String? {
        arguments.first(where: { $0.hasPrefix("--capture-appearance=") })?
            .replacingOccurrences(of: "--capture-appearance=", with: "")
    }
    static var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    static var preferencesSuiteName: String? {
        guard isEnabled, let screen, let appearance else { return nil }
        return "com.neven.gofly.capture-ui.\(screen).\(appearance).\(ProcessInfo.processInfo.processIdentifier)"
    }
}

private actor CaptureChecker: MacChecking {
    private var d13DeviceListRequests = 0
    private var screen: String? { CaptureLaunchOptions.screen }

    func check(_ request: CheckRequest) async throws -> Data {
        if Bundle.main.bundleIdentifier?.contains("capture-loading") == true {
            try? await Task.sleep(for: .milliseconds(900))
        }
        let setupScreens: Set<String> = ["E01", "E02", "E03", "E04", "E05", "E06", "E07"]
        let teamCount = screen == "E08" ? 2 : (screen.map(setupScreens.contains) == true ? 0 : 1)
        let teams: [[String: Any]] = (0..<teamCount).map { index in
            ["teamID": index == 0 ? "ABCDE12345" : "FGHIJ67890",
             "teamName": index == 0 ? "Neven" : "ACME Ltd",
             "isFreeProvisioningTeam": index == 0]
        }
        let failingIDs: Set<String>
        switch screen {
        case "E01", "E03", "E04":
            failingIDs = ["xcode-installed", "xcode-first-launch", "ios-platform", "apple-account"]
        case "E02":
            failingIDs = ["macos-version", "xcode-installed", "xcode-first-launch", "ios-platform", "apple-account"]
        case "E05":
            failingIDs = ["xcode-first-launch", "ios-platform", "apple-account"]
        case "E06":
            failingIDs = ["ios-platform", "apple-account"]
        case "E07":
            failingIDs = ["apple-account"]
        default:
            failingIDs = []
        }
        let definitions: [(String, String)] = [
            ("macos-version", "macOS 版本"),
            ("available-space", "可用空間"),
            ("xcode-installed", "Xcode"),
            ("xcode-first-launch", "Xcode 元件"),
            ("ios-platform", "iOS 平台"),
            ("apple-account", "Apple 帳號"),
        ]
        let checks: [[String: Any]] = definitions.map { id, title in
            let passed = !failingIDs.contains(id)
            let detail: String
            if id == "available-space" { detail = "需要約 40 GB・目前 212 GB" }
            else if passed {
                switch id {
                case "macos-version": detail = "符合 Xcode 需求"
                case "xcode-installed": detail = "已安裝"
                case "xcode-first-launch": detail = "已完成"
                case "ios-platform": detail = "已下載"
                case "apple-account": detail = "已登入"
                default: detail = "待確認"
                }
            } else {
                switch id {
                case "macos-version": detail = "低於 Xcode 最低需求"
                case "xcode-installed": detail = "尚未安裝"
                case "xcode-first-launch": detail = "尚未完成"
                case "ios-platform": detail = "尚未下載"
                case "apple-account": detail = "尚未登入"
                default: detail = "待確認"
                }
            }
            return ["id": id, "title": title, "detail": detail,
                    "passed": passed, "status": passed ? "passed" : "failed"]
        }
        let payload: [String: Any]
        switch request.action {
        case .environment:
            payload = ["ready": checks.allSatisfy { $0["passed"] as? Bool == true } && !teams.isEmpty,
                       "checks": checks, "teams": teams,
                       "xcodeVersion": "27.1", "projectVersion": "1.0.0", "projectBuild": "24"]
        case .devices:
            let nevenUSB: [String: Any] = ["id": "capture-secondary", "name": "Neven 的 iPhone", "transport": "usb", "osVersion": "27.0.1"]
            let renewalUSB: [String: Any] = ["id": "00008110-0000000000000006", "name": "Neven 的 iPhone", "transport": "usb", "osVersion": "27.0.1"]
            let renewalWiFi: [String: Any] = ["id": "00008110-0000000000000014", "name": "測試 iPhone", "modelName": "iPhone 14",
                                              "transport": "wifi", "osVersion": "27.0.1"]
            let testWiFi: [String: Any] = ["id": "capture-device", "name": "測試 iPhone", "modelName": "iPhone 14",
                                           "transport": "wifi", "osVersion": screen == "D12" ? "26.1" : "27.0.1"]
            let mainUSB: [String: Any] = ["id": "capture-device", "name": "Neven 的 iPhone", "transport": "usb", "osVersion": "27.0.1"]
            let onboardingUSB: [String: Any] = ["id": ["D05", "D06", "D07"].contains(screen ?? "") ? "aaaaaaaa-aaaaaaaaaaaaaaaa" : "capture-device", "name": "Neven 的 iPhone", "modelName": "iPhone 15 Pro", "transport": "usb", "osVersion": "27.0.1"]
            let devices: [[String: Any]]
            switch screen {
            case "E09": devices = [mainUSB]
            case "D02", "D03", "D04", "D05", "D06", "D07": devices = [onboardingUSB]
            case "D08": devices = [["id": "capture-device", "name": "Neven 的 iPhone", "transport": "wifi", "osVersion": "27.0.1"],
                                   ["id": "capture-secondary", "name": "測試 iPhone", "transport": "usb", "osVersion": "27.0.1"]]
            case "D09": devices = [mainUSB]
            case "D10", "D11": devices = [renewalUSB, renewalWiFi]
            case "D12": devices = [nevenUSB, testWiFi]
            case "D13":
                d13DeviceListRequests += 1
                devices = d13DeviceListRequests == 1 ? [nevenUSB, testWiFi] : [nevenUSB]
            default: devices = []
            }
            payload = ["devices": devices]
        case .inspect:
            if screen == "D02" { throw CheckFailure.service("trust-required") }
            let isAutomaticRenewalTarget = (screen == "D10" || screen == "D11") &&
                request.deviceID == "00008110-0000000000000014"
            let isAutomaticRenewalScreen = screen == "D10" || screen == "D11"
            let installed = isAutomaticRenewalScreen ? isAutomaticRenewalTarget
                : (screen == "D08" || screen == "D09" || screen == "D13" || request.deviceID == "capture-secondary")
            let developerMode: Any = screen == "D03" ? false : true
            let days = (screen == "D09" || screen == "D13" || isAutomaticRenewalTarget) ||
                (screen == "D08" && request.deviceID == "capture-secondary") ? 2 : 6
            let expiresAt = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
            let appVersion: Any = installed ? "1.0.0" : NSNull()
            let appBuild: Any = installed ? (screen == "D09" || request.deviceID == "capture-secondary" ? "22" : "24") : NSNull()
            let expiry: Any = installed ? expiresAt : NSNull()
            let deviceName = request.deviceID == "capture-secondary" ? "Neven 的 iPhone"
                : (request.deviceID == "00008110-0000000000000014" ? "測試 iPhone"
                : (screen == "D08" || screen == "D10" || screen == "D11" || screen == "D12" || screen == "D13"
                    ? "測試 iPhone" : "Neven 的 iPhone"))
            payload = ["device": ["id": request.deviceID ?? "capture-device", "name": deviceName,
                                   "modelName": screen == "D12" ? "iPhone 14" : "iPhone 15 Pro",
                                   "transport": request.transport?.rawValue ?? "usb",
                                   "osVersion": screen == "D12" ? "26.1" : "27.0.1"],
                       "developerMode": developerMode, "installed": installed,
                       "vpnInstalled": installed ? true : false,
                       "appVersion": appVersion,
                       "appBuild": appBuild,
                       "expiresAt": expiry,
                       "teamID": "ABCDE12345"]
        case .registeredDevices:
            payload = ["devices": []]
        }
        return try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID, "status": "ok", "payload": payload,
        ])
    }
}

private struct CaptureSetupRunner: MacSetupRunning {
    let journal: CaptureSetupJournal

    func run(_ request: MacSetupRequest) async throws -> Data {
        switch request.action {
        case .preflight:
            try await journal.record(request)
            return try response(request, stage: .preflight, outcome: .ready,
                                proof: (false, false, false), includeApp: false)
        case .apply:
            if CaptureLaunchOptions.screen == "D07" || CaptureLaunchOptions.screen == "D11" {
                await journal.update(stage: .complete, proof: (true, true, true))
                return try completionResponse(request)
            }
            let stage: MacSetupStage
            if CaptureLaunchOptions.screen == "D06" { stage = .handoff }
            else if CaptureLaunchOptions.screen == "D10" { stage = .install }
            else { stage = .artifact }
            let proof = stage == .handoff ? (true, true, true) : (false, false, false)
            await journal.update(stage: stage, proof: proof)
            do { try await Task.sleep(for: .seconds(60)) }
            catch { throw MacSetupFailure.cancelled }
            return try await currentResponse(request)
        case .status:
            return try await currentResponse(request)
        }
    }

    private func currentResponse(_ request: MacSetupRequest) async throws -> Data {
        let state = await journal.current
        return try response(request, stage: state.stage, outcome: .unknown,
                            proof: state.proof, includeApp: false)
    }

    private func completionResponse(_ request: MacSetupRequest) throws -> Data {
        let expiresAt = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        return try response(request, stage: .complete, outcome: .confirmed,
                            proof: (true, true, true), includeApp: true, expiresAt: expiresAt,
                            receipt: String(repeating: "c", count: 64))
    }

    private func response(_ request: MacSetupRequest, stage: MacSetupStage, outcome: MacSetupOutcome,
                         proof: (Bool, Bool, Bool), includeApp: Bool,
                         expiresAt: String? = nil, receipt: String? = nil) throws -> Data {
        guard let setupID = request.setupID, let deviceID = request.deviceID,
              let teamID = request.teamID else { throw MacSetupFailure.invalidRequest }
        var payload: [String: Any] = [
            "stage": stage.rawValue, "outcome": outcome.rawValue,
            "proof": ["installationConfirmed": proof.0, "pairingImported": proof.1, "supportObserved": proof.2],
            "teamID": teamID,
        ]
        if includeApp {
            payload["app"] = ["bundleID": MacBundleIdentifier.forTeamID(teamID) ?? "",
                              "build": "24", "profileSHA256": String(repeating: "a", count: 64),
                              "executableSHA256": String(repeating: "b", count: 64)]
        }
        if let expiresAt { payload["expiresAt"] = expiresAt }
        if let receipt { payload["receiptSHA256"] = receipt }
        return try JSONSerialization.data(withJSONObject: [
            "action": request.action.rawValue, "requestID": request.requestID.uuidString,
            "setupID": setupID.uuidString, "deviceID": deviceID,
            "mode": (request.mode ?? .install).rawValue,
            "transport": request.transport?.rawValue ?? "usb", "status": "ok", "payload": payload,
        ])
    }
}

private actor CaptureSetupJournal: MacSetupJournalReading {
    struct Snapshot {
        let stage: MacSetupStage
        let proof: (Bool, Bool, Bool)
    }
    private var identity: MacSetupTransactionIdentity?
    private var stage: MacSetupStage = .preflight
    private var proof = (false, false, false)
    let screen: String?

    init(screen: String?) { self.screen = screen }

    private func d14Identity() throws -> MacSetupTransactionIdentity {
        try MacSetupTransactionIdentity(setupID: UUID(uuidString: "DD140000-0000-4000-8000-000000000014")!,
                                        deviceID: "00008110-0000000000000014", mode: .renew,
                                        transport: .wifi,
                                        teamID: "ABCDE12345")
    }

    var current: Snapshot { Snapshot(stage: stage, proof: proof) }

    func record(_ request: MacSetupRequest) throws {
        guard let setupID = request.setupID, let deviceID = request.deviceID,
              let teamID = request.teamID else { throw MacSetupFailure.invalidRequest }
        identity = try MacSetupTransactionIdentity(setupID: setupID, deviceID: deviceID,
                                            mode: request.mode ?? .install,
                                            transport: request.transport ?? .usb, teamID: teamID)
    }

    func update(stage: MacSetupStage, proof: (Bool, Bool, Bool)) {
        self.stage = stage
        self.proof = proof
    }

    func readPendingTransaction() async throws -> MacSetupTransactionIdentity? {
        if screen == "D14" { return try d14Identity() }
        return identity
    }
    func readState() async throws -> MacSetupJournalState {
        if screen == "D14" {
            let snapshot = MacSetupSnapshot(mode: .renew, stage: .install, outcome: .unknown,
                                            appBuild: "24", teamID: "ABCDE12345", expiresAt: nil,
                                            receiptSHA256: nil, installationConfirmed: false,
                                            pairingImported: false, supportObserved: false, errorCode: "wifi-device-not-found")
            return MacSetupJournalState(pendingTransaction: try d14Identity(), pendingSnapshot: snapshot, completed: nil)
        }
        return MacSetupJournalState(pendingTransaction: identity, completed: nil)
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        if let suite = CaptureLaunchOptions.preferencesSuiteName {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
