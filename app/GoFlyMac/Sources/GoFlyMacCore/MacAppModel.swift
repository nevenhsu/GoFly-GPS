import Foundation
import Observation

public enum MacRoute: Equatable, Sendable {
    case startup
    case environment(MacEnvironmentStep)
    case environmentSummary
    case deviceList
    case deviceDetail
    case install
}

public enum MacEnvironmentStep: String, CaseIterable, Identifiable, Sendable {
    case overview, updateMacOS, getXcode, waitForXcode, firstLaunch, iosPlatform, appleAccount, selectTeam
    public var id: String { rawValue }
}

public enum MacDevicePageState: Equatable, Sendable {
    case noDevice, chooseDevice, checking, inspectRequired, trustRequired
    case developerModeRequired, readyToInstall, installed, updateAvailable
    case wifiNeedsUSB, wifiUnavailable, restartRequired
}

@MainActor @Observable
public final class MacAppModel {
    public private(set) var route: MacRoute = .startup
    public private(set) var environment: MacEnvironment?
    public private(set) var devices: [ConnectedDevice] = []
    public private(set) var inspection: DeviceInspection?
    public private(set) var inspectionsByConnection: [String: DeviceInspection] = [:]
    public private(set) var selectedID: String?
    public private(set) var selectedTransport: ConnectedDevice.Transport?
    public private(set) var selectedDeviceSnapshot: ConnectedDevice?
    private var checkingBusy = false
    public private(set) var isCancellingCheck = false
    public var isChecking: Bool { checkingBusy }
    public let setup: MacSetupModel?
    private var restoringOperations = false
    public private(set) var failure: CheckFailure?
    public private(set) var firstInstall = true
    public let isFirstOpen: Bool
    public private(set) var selectedTeamID: String?
    public private(set) var hasCheckedEnvironment = false
    public private(set) var autoRenewEnabled: Bool
    public private(set) var networkAvailable = false
    public private(set) var hasNetworkStatus = false
    private var autoRenewCheckInProgress = false
    @ObservationIgnored private let live: any MacChecking
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeCheckID: UUID?
    @ObservationIgnored private var inspectAfterDeviceRefresh = false
    private static let selectedTeamKey = "gofly.mac.selectedTeamID"
    private static let lastManagedDeviceIDKey = "gofly.mac.lastManagedDeviceID"
    private static let lastManagedDeviceTransportKey = "gofly.mac.lastManagedDeviceTransport"
    private static let hasOpenedBeforeKey = "gofly.mac.hasOpenedBefore"
    private static let autoRenewEnabledKey = "gofly.mac.autoRenewEnabled"
    private static let autoRenewLastCheckKey = "gofly.mac.autoRenewLastCheck"

    public init(live: any MacChecking, setup: MacSetupModel? = nil,
                preferences: UserDefaults = .standard) {
        self.live = live
        self.setup = setup
        self.preferences = preferences
        self.selectedTeamID = preferences.string(forKey: Self.selectedTeamKey)
        self.autoRenewEnabled = preferences.object(forKey: Self.autoRenewEnabledKey) as? Bool ?? true
        self.isFirstOpen = !preferences.bool(forKey: Self.hasOpenedBeforeKey)
        preferences.set(true, forKey: Self.hasOpenedBeforeKey)
    }

    public var busy: Bool {
        checkingBusy || restoringOperations || autoRenewCheckInProgress || setup?.isBusy == true
    }
    public var setupLocksDevice: Bool {
        restoringOperations || setup?.locksDevice == true
    }
    private var activeOperationPage: MacRoute {
        setup?.hasUnfinishedTransaction == true ? .deviceDetail : .install
    }

    public func restoreSetup() async {
        await setup?.restore()
        if let identity = setup?.pendingTransaction {
            selectedID = identity.deviceID
            let transport = setup?.pendingTransaction?.transport ?? .usb
            selectedTransport = transport
            selectedDeviceSnapshot = ConnectedDevice(id: identity.deviceID, name: "", transport: transport)
            selectedTeamID = identity.teamID
            preferences.set(identity.teamID, forKey: Self.selectedTeamKey)
            firstInstall = identity.mode == .install
            route = setup?.hasUnfinishedTransaction == true ? .deviceDetail : .install
        } else if setup?.failure != nil {
            firstInstall = true
            route = .install
        }
    }

    public var ready: Bool { environment?.ready == true && selectedTeam != nil && !busy }
    public var canBeginEnvironmentPreparation: Bool {
        guard let check = environment?.checks.first(where: { $0.id == "available-space" }) else { return false }
        return check.passed && check.status != .unknown && !busy
    }
    public var selectedTeam: MacTeam? {
        guard let environment, let selectedTeamID else { return nil }
        return environment.teams.first { $0.teamID == selectedTeamID }
    }
    public var selected: ConnectedDevice? {
        if let inspection, inspection.device.id.lowercased() == selectedID?.lowercased(),
           selectedTransport == nil || inspection.device.transport == selectedTransport { return inspection.device }
        if let device = devices.first(where: {
            $0.id.lowercased() == selectedID?.lowercased() && (selectedTransport == nil || $0.transport == selectedTransport)
        }) { return device }
        guard let selectedDeviceSnapshot,
              selectedDeviceSnapshot.id.lowercased() == selectedID?.lowercased(),
              selectedTransport == nil || selectedDeviceSnapshot.transport == selectedTransport else { return nil }
        return selectedDeviceSnapshot
    }
    public var visibleDevices: [ConnectedDevice] { ConnectedDevice.unique(devices, usbOnly: firstInstall) }
    public var sidebarDevices: [ConnectedDevice] {
        var result = visibleDevices
        if setup?.hasUnfinishedTransaction == true, let selectedDeviceSnapshot,
           !result.contains(where: { $0.connectionID == selectedDeviceSnapshot.connectionID }) {
            result.append(selectedDeviceSnapshot)
        }
        if devicePageState == .wifiUnavailable, let selectedDeviceSnapshot,
           !result.contains(where: { $0.connectionID == selectedDeviceSnapshot.connectionID }) {
            result.append(selectedDeviceSnapshot)
        }
        return result
    }
    public var availableConnections: [ConnectedDevice] { ConnectedDevice.connectionChoices(devices, usbOnly: firstInstall) }
    public var mayInspect: Bool { ready && selected != nil }
    public var installedOnFirstInstall: Bool {
        firstInstall && inspection?.installed == true
    }

    public var devicePageState: MacDevicePageState {
        if setup?.hasUnfinishedTransaction == true { return .restartRequired }
        guard selected != nil else { return visibleDevices.isEmpty ? .noDevice : .chooseDevice }
        if isChecking { return .checking }
        if selectedTransport == .wifi, case .service(let code)? = failure,
           ["device-disconnected", "wifi-device-not-found", "wifi-pairing-unknown",
            "wifi-support-unavailable", "wifi-renew-unknown", "usb-device-not-found"].contains(code) {
            return .wifiUnavailable
        }
        if case .service(let code)? = failure, code == "trust-required" || code == "usb-lockdown-failed" {
            return .trustRequired
        }
        if failure != nil { return .inspectRequired }
        guard let inspection else { return .inspectRequired }
        if inspection.installed == true { return projectIsNewer ? .updateAvailable : .installed }
        if selectedTransport == .wifi, inspection.installed == false { return .wifiNeedsUSB }
        if inspection.developerMode != true { return .developerModeRequired }
        if inspection.installed == false, selectedTransport == .usb { return .readyToInstall }
        return .inspectRequired
    }

    public var signingDaysRemaining: Int? {
        signingExpiryDate.map(Self.signingDaysLeft)
    }

    /// Free Personal Team signing lasts 7 days: whole days left, rounded up,
    /// capped at 7. Negative means already expired.
    static func signingDaysLeft(until date: Date) -> Int {
        min(7, Int((date.timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    public func signingExpiryText(for device: ConnectedDevice) -> String {
        guard let days = signingDaysRemaining(for: device) else { return "待確認" }
        return days < 0 ? "已過期" : "剩 \(days) 天"
    }

    public func signingDaysRemaining(for device: ConnectedDevice) -> Int? {
        let expiry: String?
        let observed = inspection?.device.connectionID == device.connectionID
            ? inspection : inspectionsByConnection[device.connectionID]
        expiry = observed?.expiresAt ?? (device.id.lowercased() == selectedID?.lowercased()
            ? setup?.snapshot?.expiresAt ?? setup?.lastCompleted?.expiresAt : nil)
        guard let expiry, let date = ISO8601DateFormatter().date(from: expiry) else { return nil }
        return Self.signingDaysLeft(until: date)
    }

    public func setAutoRenewEnabled(_ enabled: Bool) {
        autoRenewEnabled = enabled
        preferences.set(enabled, forKey: Self.autoRenewEnabledKey)
    }

    public func autoRenewEnabled(for device: ConnectedDevice) -> Bool {
        preferences.object(forKey: autoRenewKey(for: device)) as? Bool ?? autoRenewEnabled
    }

    public func setAutoRenewEnabled(_ enabled: Bool, for device: ConnectedDevice) {
        preferences.set(enabled, forKey: autoRenewKey(for: device))
    }

    public func setNetworkAvailable(_ available: Bool) {
        hasNetworkStatus = true
        networkAvailable = available
    }

    public func showWifiRenewUnavailable(_ code: String) {
        guard selectedTransport == .wifi,
              ["wifi-device-not-found", "wifi-pairing-unknown", "wifi-support-unavailable",
               "wifi-renew-unknown"].contains(code),
              setup?.hasUnfinishedTransaction != true else { return }
        failure = .service(code)
        route = .deviceDetail
    }

    private func autoRenewKey(for device: ConnectedDevice) -> String {
        "\(Self.autoRenewEnabledKey).\(device.id.lowercased())"
    }

    /// Runs at launch and on the 24-hour scheduler. The timestamp is persisted
    /// before checking eligibility, so an unavailable device or failed attempt
    /// cannot cause rapid retries after a relaunch.
    public func checkAutomaticRenewal(now: Date = Date()) async {
        let lastCheck = preferences.object(forKey: Self.autoRenewLastCheckKey) as? Date
        guard MacAutoRenewPolicy.isCheckDue(now: now, lastCheck: lastCheck) else { return }
        guard hasNetworkStatus else { return }
        preferences.set(now, forKey: Self.autoRenewLastCheckKey)
        guard autoRenewEnabled, networkAvailable, environment?.ready == true,
              !busy, !setupLocksDevice, setup?.isRestored == true,
              let teamID = selectedTeam?.teamID else { return }

        autoRenewCheckInProgress = true
        defer { autoRenewCheckInProgress = false }
        do {
            let devicesRequest = CheckRequest(action: .devices)
            let devicesData = try await live.check(devicesRequest)
            let deviceList = try ResponseDecoder.decode(devicesData, for: devicesRequest, as: DeviceList.self)
            let choices = ConnectedDevice.connectionChoices(deviceList.devices, usbOnly: false)
            if choices.isEmpty,
               let previousID = preferences.string(forKey: Self.lastManagedDeviceIDKey),
               preferences.string(forKey: Self.lastManagedDeviceTransportKey) == ConnectedDevice.Transport.wifi.rawValue {
                let unavailable = ConnectedDevice(id: previousID, name: "", transport: .wifi)
                selectedID = unavailable.id
                selectedTransport = .wifi
                selectedDeviceSnapshot = unavailable
                firstInstall = false
                failure = .service("wifi-device-not-found")
                route = .deviceDetail
                return
            }
            let groups = Dictionary(grouping: choices, by: { $0.id.lowercased() })
            let candidates = groups.values.compactMap { connections in
                connections.first(where: { $0.transport == .usb }) ?? connections.first
            }.sorted { ($0.name, $0.id.lowercased()) < ($1.name, $1.id.lowercased()) }

            for device in candidates where autoRenewEnabled(for: device) {
                guard !setupLocksDevice else { return }
                let inspectRequest = CheckRequest(action: .inspect, deviceID: device.id,
                                                  transport: device.transport, teamID: teamID)
                let inspectData = try await live.check(inspectRequest)
                let inspection = try ResponseDecoder.decode(inspectData, for: inspectRequest, as: DeviceInspection.self)
                guard inspection.device.id.lowercased() == device.id.lowercased(),
                      inspection.device.transport == device.transport,
                      inspection.teamID == teamID else { continue }
                let expiry = inspection.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                guard MacAutoRenewPolicy.shouldBegin(
                    now: now, expiresAt: expiry,
                    enabled: autoRenewEnabled(for: device),
                    installed: inspection.installed == true,
                    reachable: true,
                    networkAvailable: networkAvailable,
                    operationInProgress: false
                ) else { continue }

                selectedID = device.id
                selectedTransport = device.transport
                selectedDeviceSnapshot = inspection.device
                preferences.set(device.id.lowercased(), forKey: Self.lastManagedDeviceIDKey)
                preferences.set(device.transport.rawValue, forKey: Self.lastManagedDeviceTransportKey)
                self.inspection = inspection
                inspectionsByConnection[inspection.device.connectionID] = inspection
                firstInstall = false
                autoRenewCheckInProgress = false
                startRenew(automatic: true)
                return
            }
        } catch {
            // Automatic checks are read-only until beginRenew. Keep the normal
            // device page available and wait for the next scheduled check.
        }
    }

    public var installStatus: String {
        guard let inspection else { return "尚未檢查" }
        switch inspection.installed { case true: return "已偵測到 App"; case false: return "未偵測到 App"; default: return "安裝狀態待確認" }
    }

    public func navigate(_ destination: MacRoute) {
        guard !busy else { return }
        if setupLocksDevice && destination != .startup && destination != activeOperationPage && destination != .environmentSummary {
            route = activeOperationPage; return
        }
        if case .environment = destination { route = destination; failure = nil; return }
        if destination != .startup && destination != .environmentSummary &&
            !(destination == activeOperationPage && setupLocksDevice) &&
            !(destination == .install && setup?.hasRecordedTransaction == true) &&
            environment?.ready != true {
            route = firstIncompleteRoute(environment); return
        }
        route = destination; failure = nil
    }

    public func openRecordedOperation() {
        navigate(.install)
    }

    /// Starts the one read-only launch check and routes directly to the first
    /// required screen. The view may keep E00 hidden when this finishes quickly.
    public func beginLaunchCheck() {
        route = .startup
        perform(.environment) { data, request in
            let value = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
            self.applyEnvironment(value)
            self.route = self.launchRoute(for: value)
        }
    }

    public func startEnvironmentPreparation() {
        guard !busy else { return }
        route = firstIncompleteRoute(environment)
    }

    public func waitForXcodeInstall() {
        guard !busy, route == .environment(.getXcode) else { return }
        route = .environment(.waitForXcode)
    }

    private func launchRoute(for value: MacEnvironment) -> MacRoute {
        guard failure == nil else { return .startup }
        if setup?.hasUnfinishedTransaction == true { return .deviceDetail }
        if isFirstOpen, check("xcode-installed", in: value)?.passed == false {
            return .environment(.overview)
        }
        return firstIncompleteRoute(value)
    }

    private func firstIncompleteRoute(_ value: MacEnvironment?) -> MacRoute {
        guard let value else { return .environment(.overview) }
        let routes: [(String, MacEnvironmentStep)] = [
            ("macos-version", .updateMacOS), ("available-space", .overview),
            ("xcode-installed", .getXcode), ("xcode-first-launch", .firstLaunch),
            ("ios-platform", .iosPlatform), ("apple-account", .appleAccount)
        ]
        for (id, step) in routes {
            guard let check = check(id, in: value), check.passed else { return .environment(step) }
        }
        guard !value.teams.isEmpty else { return .environment(.appleAccount) }
        guard selectedTeam != nil else { return .environment(.selectTeam) }
        return .deviceList
    }

    private func check(_ id: String, in environment: MacEnvironment) -> EnvironmentCheck? {
        environment.checks.first { $0.id == id }
    }

    public func select(_ id: String, transport: ConnectedDevice.Transport? = nil) {
        guard !busy, !setupLocksDevice,
              let choice = availableConnections.first(where: { $0.id == id && (transport == nil || $0.transport == transport) }) else { return }
        if selectedID?.lowercased() != id.lowercased() || selectedTransport != choice.transport {
            setup?.resetSelection()
        }
        selectedID = id; selectedTransport = choice.transport
        selectedDeviceSnapshot = choice
        preferences.set(choice.id.lowercased(), forKey: Self.lastManagedDeviceIDKey)
        preferences.set(choice.transport.rawValue, forKey: Self.lastManagedDeviceTransportKey)
        inspection = nil; failure = nil
    }

    public func openDevices(firstInstall: Bool) {
        showDevices(firstInstall: firstInstall, ignoreSetupLock: false)
    }

    /// Pure navigation back to the device list.  An unavailable environment or
    /// a blocked journal must not strand the user on an error page.
    public func returnToDevices() {
        showDevices(firstInstall: false, ignoreSetupLock: true)
    }

    private func showDevices(firstInstall: Bool, ignoreSetupLock: Bool) {
        guard !busy, ignoreSetupLock || !setupLocksDevice else { return }
        setup?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; selectedTransport = nil
        selectedDeviceSnapshot = nil; inspection = nil
        route = .deviceList
        if environment?.ready == true { refreshDevices() }
    }

    /// Moves from the first-install refusal to the selected phone's management
    /// page without running another inspection or starting setup.
    public func openSelectedDevicePage() {
        guard !busy, !setupLocksDevice, let device = selected else { return }
        setup?.resetSelection()
        firstInstall = false
        selectedID = device.id
        selectedTransport = device.transport
        route = .deviceDetail
        failure = nil
    }

    public func checkEnvironment() {
        guard !busy else { return }
        perform(.environment) { data, request in
            let value = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
            self.applyEnvironment(value)
            switch self.route {
            case .startup:
                self.route = self.launchRoute(for: value)
            case .environment(.selectTeam), .environmentSummary:
                break
            case .environment(.waitForXcode):
                if self.check("xcode-installed", in: value)?.passed == true {
                    self.route = self.firstIncompleteRoute(value)
                }
            case .environment:
                self.route = self.firstIncompleteRoute(value)
            default:
                break
            }
        }
    }

    private func applyEnvironment(_ value: MacEnvironment) {
        environment = value
        hasCheckedEnvironment = true
        if let selectedTeamID, value.teams.contains(where: { $0.teamID == selectedTeamID }) {
            return
        }
        if value.teams.count == 1 {
            selectedTeamID = value.teams[0].teamID
            preferences.set(value.teams[0].teamID, forKey: Self.selectedTeamKey)
        } else {
            selectedTeamID = nil
            preferences.removeObject(forKey: Self.selectedTeamKey)
        }
    }

    public func selectTeam(_ teamID: String) {
        guard let team = environment?.teams.first(where: { $0.teamID == teamID }) else { return }
        selectedTeamID = team.teamID
        preferences.set(team.teamID, forKey: Self.selectedTeamKey)
    }

    public func refreshDevices() {
        guard !busy, !setupLocksDevice else { return }
        setup?.resetSelection()
        let previousSelection = selected
        devices = []; failure = nil
        if previousSelection?.transport != .wifi { inspection = nil }
        perform(.devices) { data, request in
            let choices = ConnectedDevice.connectionChoices(
                try ResponseDecoder.decode(data, for: request, as: DeviceList.self).devices,
                usbOnly: false
            )
            self.devices = choices
            if let previousSelection {
                let samePhone = choices.first { $0.id.lowercased() == previousSelection.id.lowercased() }
                if let match = choices.first(where: {
                    $0.id.lowercased() == previousSelection.id.lowercased() && $0.transport == previousSelection.transport
                }) {
                    self.selectedDeviceSnapshot = match
                    self.selectedID = match.id
                    self.selectedTransport = match.transport
                    self.inspectAfterDeviceRefresh = true
                } else if previousSelection.transport == .wifi, let usb = samePhone, usb.transport == .usb {
                    self.selectedDeviceSnapshot = usb
                    self.selectedID = usb.id
                    self.selectedTransport = .usb
                    self.route = .deviceDetail
                    self.inspectAfterDeviceRefresh = true
                } else if previousSelection.transport == .wifi, !self.firstInstall {
                    self.selectedDeviceSnapshot = previousSelection
                    self.selectedID = previousSelection.id
                    self.selectedTransport = .wifi
                    self.failure = .service("device-disconnected")
                    self.route = .deviceDetail
                } else {
                    self.selectedDeviceSnapshot = nil
                    self.selectedID = nil
                    self.selectedTransport = nil
                    if self.route == .deviceDetail { self.route = .deviceList }
                }
            } else if self.route == .deviceList, self.firstInstall,
                      self.visibleDevices.count == 1, let device = self.visibleDevices.first {
                self.selectedID = device.id
                self.selectedTransport = device.transport
                self.selectedDeviceSnapshot = device
                self.route = .deviceDetail
                self.inspectAfterDeviceRefresh = true
            }
        }
    }

    public func inspectSelected() {
        guard let device = selected, ready, !setupLocksDevice else { return }
        selectedDeviceSnapshot = device
        route = .deviceDetail
        if inspection?.device.id.lowercased() != device.id.lowercased() ||
            inspection?.device.transport != device.transport {
            inspection = nil
        }
        perform(.inspect, deviceID: device.id, transport: device.transport, teamID: selectedTeam?.teamID) { data, request in
            let result = try ResponseDecoder.decode(data, for: request, as: DeviceInspection.self)
            guard result.device.id.lowercased() == device.id.lowercased(),
                  result.device.transport == device.transport else { throw CheckFailure.invalidResponse }
            self.inspection = result
            self.selectedDeviceSnapshot = result.device
            self.inspectionsByConnection[result.device.connectionID] = result
            self.route = .deviceDetail
        }
    }

    public func beginFirstInstall() {
        guard !busy, devicePageState == .readyToInstall,
              let device = selected, device.transport == .usb,
              let setup, setup.isRestored,
              let teamID = selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: teamID) else { return }
        do {
            try setup.configure(deviceID: device.id, options: options)
            firstInstall = true
            route = .install
        } catch {
            failure = .invalidResponse
        }
    }

    public func restartInterruptedSetup() {
        guard !busy, let setup, setup.isRestored, setup.hasUnfinishedTransaction,
              let identity = setup.pendingTransaction,
              let options = try? MacSetupOptions(teamID: identity.teamID) else { return }
        do {
            try setup.beginRestart(deviceID: identity.deviceID, options: options)
            firstInstall = identity.mode == .install
            route = .install
        } catch {
            failure = .invalidResponse
        }
    }

    public func openInterruptedSetup() {
        guard let identity = setup?.pendingTransaction, setup?.hasUnfinishedTransaction == true else { return }
        selectedID = identity.deviceID
        let transport = setup?.pendingTransaction?.transport ?? .usb
        selectedTransport = transport
        selectedDeviceSnapshot = ConnectedDevice(id: identity.deviceID, name: "", transport: transport)
        selectedTeamID = identity.teamID
        firstInstall = identity.mode == .install
        route = .deviceDetail
    }

    #if DEBUG
    public func prepareD14Capture(usbDevice: ConnectedDevice, wifiDevice: ConnectedDevice) {
        devices = [usbDevice, wifiDevice]
        selectedID = wifiDevice.id
        selectedTransport = wifiDevice.transport
        selectedDeviceSnapshot = wifiDevice
        let expiryDate = Calendar.current.date(byAdding: .day, value: 6, to: Date())
        let expiry = expiryDate.map { ISO8601DateFormatter().string(from: $0) }
        inspectionsByConnection[usbDevice.connectionID] = DeviceInspection(
            device: usbDevice, developerMode: true, installed: true, vpnInstalled: true,
            appVersion: "1.0.0", appBuild: "24", teamID: selectedTeamID, expiresAt: expiry
        )
        firstInstall = false
        route = .deviceDetail
    }
    #endif

    public func completeFirstInstall() {
        guard setup?.snapshot?.isComplete == true, !busy else { return }
        setup?.resetSelection()
        firstInstall = false
        inspection = nil
        route = .deviceDetail
        inspectSelected()
    }

    public var projectIsNewer: Bool {
        let projectVersion = environment?.projectVersion
        let projectBuild = environment?.projectBuild
        let installedVersion = inspection?.appVersion
        let installedBuild = inspection?.appBuild
        if let projectBuild, let projectBuildNumber = Int(projectBuild),
           let installedBuild, let installedBuildNumber = Int(installedBuild),
           projectBuildNumber != installedBuildNumber {
            return projectBuildNumber > installedBuildNumber
        }
        return projectVersion != nil && installedVersion != nil && projectVersion != installedVersion
    }

    public var renewButtonTitle: String {
        projectIsNewer ? "更新 GoFly" : "延長簽名期限"
    }

    public var signingExpiryISO: String? {
        inspection?.expiresAt ?? setup?.snapshot?.expiresAt ?? setup?.lastCompleted?.expiresAt
    }

    public var signingExpiryDate: Date? {
        signingExpiryISO.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    public var signingExpiryText: String {
        guard let date = signingExpiryDate else { return "待確認" }
        let text = date.formatted(Date.FormatStyle(date: .numeric, time: .shortened)
            .locale(Locale(identifier: "zh_TW")))
        let days = Self.signingDaysLeft(until: date)
        return days < 0 ? "\(text)（已過期）" : "\(text)（剩餘 \(days) 天）"
    }

    public func startRenew() {
        startRenew(automatic: false)
    }

    private func startRenew(automatic: Bool) {
        guard !busy, let device = selected, inspection?.installed == true,
              let setup, setup.isRestored, !setup.isBusy,
              let team = selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: team) else { return }
        if setup.hasRecordedTransaction && setup.snapshot?.canReplaceCompletedTransaction != true {
            route = .install
            return
        }
        do {
            try setup.beginRenew(deviceID: device.id, options: options,
                                 transport: device.transport, automatic: automatic)
            route = .install
        } catch {
            route = .install
        }
    }

    public func cancel() {
        generation = UUID()
        if checkingBusy { isCancellingCheck = true }
        task?.cancel()
        inspection = nil
    }

    private func perform(_ action: CheckAction, deviceID: String? = nil, transport: ConnectedDevice.Transport? = nil,
                         teamID: String? = nil,
                         apply: @escaping @MainActor (Data, CheckRequest) throws -> Void) {
        guard !busy else { return }
        checkingBusy = true; failure = nil
        isCancellingCheck = false
        let token = UUID(); generation = token; activeCheckID = token
        let request = CheckRequest(action: action, deviceID: deviceID, transport: transport,
                                   teamID: teamID ?? (action == .inspect ? selectedTeamID : nil))
        task = Task {
            defer { self.finishCheck(token) }
            do {
                let result = try await live.check(request)
                guard !Task.isCancelled, self.generation == token else { return }
                try apply(result, request)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.inspection = nil
                self.failure = error as? CheckFailure ?? .invalidResponse
                if action == .inspect { self.route = .deviceDetail }
            }
        }
    }

    private func finishCheck(_ token: UUID) {
        guard activeCheckID == token else { return }
        activeCheckID = nil
        checkingBusy = false
        isCancellingCheck = false
        task = nil
        hasCheckedEnvironment = true
        if inspectAfterDeviceRefresh {
            inspectAfterDeviceRefresh = false
            inspectSelected()
        }
    }
}
