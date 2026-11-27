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
    /// D15/D15b/D16: no usable saved IPA yet, or the user opened "Choose another IPA".
    case chooseIpa
    /// D17: GitHub has a newer signed IPA than the phone and the saved one.
    case releaseAvailable
}

public enum IpaSourceMode: String, Sendable { case url, file }

/// Where the signature field's value came from (D15b).
public enum IpaSignatureOrigin: Equatable, Sendable { case manual, sameFolder, github }

public enum IpaReleaseLookup: Equatable, Sendable { case idle, loading, loaded, unavailable }

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
    // Saved IPA and its sources (MAC-INSTALLER-SPEC §5.5).
    public private(set) var savedIpa: SavedIpa?
    public private(set) var latestRelease: IpaRelease?
    public private(set) var releaseLookup: IpaReleaseLookup = .idle
    public private(set) var ipaChooserOpen = false
    public private(set) var ipaImportBusy = false
    public private(set) var ipaFailure: CheckFailure?
    public var ipaSourceMode: IpaSourceMode = .url
    public var ipaURLText = "" { didSet { if ipaURLText != latestRelease?.ipaURL { ipaURLEdited = true } } }
    public private(set) var ipaURLEdited = false
    public private(set) var ipaFilePath: String?
    public private(set) var signatureLocation: String?
    public private(set) var signatureOrigin: IpaSignatureOrigin?
    public private(set) var signatureLookupBusy = false
    @ObservationIgnored private var ipaTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var renewAfterImport = false
    @ObservationIgnored private let live: any MacChecking
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeCheckID: UUID?
    @ObservationIgnored private var inspectAfterDeviceRefresh = false
    private var deviceNames: [String: String]
    private static let selectedTeamKey = "gofly.mac.selectedTeamID"
    private static let deviceNamesKey = "gofly.mac.deviceNames"
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
        self.deviceNames = preferences.dictionary(forKey: Self.deviceNamesKey) as? [String: String] ?? [:]
        self.isFirstOpen = !preferences.bool(forKey: Self.hasOpenedBeforeKey)
        preferences.set(true, forKey: Self.hasOpenedBeforeKey)
    }

    public var busy: Bool {
        checkingBusy || restoringOperations || autoRenewCheckInProgress || ipaImportBusy || setup?.isBusy == true
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
        }) { return withKnownName(device) }
        guard let selectedDeviceSnapshot,
              selectedDeviceSnapshot.id.lowercased() == selectedID?.lowercased(),
              selectedTransport == nil || selectedDeviceSnapshot.transport == selectedTransport else { return nil }
        return withKnownName(selectedDeviceSnapshot)
    }
    public var visibleDevices: [ConnectedDevice] { ConnectedDevice.unique(devices, usbOnly: firstInstall) }
    public var sidebarDevices: [ConnectedDevice] {
        var result = visibleDevices.map(withKnownName)
        // The phone being installed or restarted stays listed even when no
        // scan has seen it (for example "Start over" right after relaunch).
        if setup?.locksDevice == true, let selectedDeviceSnapshot,
           !result.contains(where: { $0.connectionID == selectedDeviceSnapshot.connectionID }) {
            result.append(withKnownName(selectedDeviceSnapshot))
        }
        if devicePageState == .wifiUnavailable, let selectedDeviceSnapshot,
           !result.contains(where: { $0.connectionID == selectedDeviceSnapshot.connectionID }) {
            result.append(withKnownName(selectedDeviceSnapshot))
        }
        return result
    }

    /// usbmux rows carry no name; the iPhone's own name (Settings › General ›
    /// About › Name) arrives with inspection and is remembered per phone.
    private func withKnownName(_ device: ConnectedDevice) -> ConnectedDevice {
        guard device.name.isEmpty, let name = deviceNames[device.id.lowercased()] else { return device }
        return ConnectedDevice(id: device.id, name: name, transport: device.transport,
                               osVersion: device.osVersion, modelName: device.modelName)
    }

    /// Phones holding the selected Team's registration slots, shown when Apple
    /// refuses a new phone. Nil until loaded or when the read fails.
    public private(set) var registeredDevices: [RegisteredDevice]?

    public func loadRegisteredDevices() {
        guard let teamID = selectedTeam?.teamID ?? setup?.pendingTransaction?.teamID else { return }
        Task {
            let request = CheckRequest(action: .registeredDevices, teamID: teamID)
            guard let data = try? await live.check(request),
                  let list = try? ResponseDecoder.decode(data, for: request, as: RegisteredDeviceList.self) else {
                registeredDevices = nil
                return
            }
            registeredDevices = list.devices.map { device in
                guard device.name.isEmpty, let name = deviceNames[device.id.lowercased()] else { return device }
                return RegisteredDevice(id: device.id, name: name)
            }
        }
    }

    private func rememberName(of device: ConnectedDevice) {
        let key = device.id.lowercased()
        guard !device.name.isEmpty, deviceNames[key] != device.name else { return }
        deviceNames[key] = device.name
        preferences.set(deviceNames, forKey: Self.deviceNamesKey)
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
        if inspection.installed == true {
            if ipaChooserOpen || savedIpaIsOlderThanInstalled || savedIpa?.supported == false { return .chooseIpa }
            if releaseIsNewer { return .releaseAvailable }
            if savedIpa == nil { return .chooseIpa }
            return projectIsNewer ? .updateAvailable : .installed
        }
        if selectedTransport == .wifi, inspection.installed == false { return .wifiNeedsUSB }
        if inspection.developerMode != true { return .developerModeRequired }
        if inspection.installed == false, selectedTransport == .usb {
            return ipaChooserOpen || savedIpa == nil || savedIpa?.supported == false ? .chooseIpa : .readyToInstall
        }
        return .inspectRequired
    }

    public var signingDaysRemaining: Int? {
        signingExpiryDate.map(Self.signingDaysLeft)
    }

    /// Whole days left, rounded up. Negative means already expired. The setup
    /// producer already caps a free Personal Team at 7 days from signing, so a
    /// paid team's profile date is shown as is.
    static func signingDaysLeft(until date: Date) -> Int {
        Int((date.timeIntervalSinceNow / 86_400).rounded(.up))
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
                // Renewal installs the saved IPA as is; never download, swap or downgrade here.
                guard let saved = savedIpa, saved.supported != false,
                      GoFlyVersionOrder.isNewer(version: inspection.appVersion, build: inspection.appBuild,
                                                than: saved.version, saved.build) != true else { continue }

                selectedID = device.id
                selectedTransport = device.transport
                selectedDeviceSnapshot = inspection.device
                preferences.set(device.id.lowercased(), forKey: Self.lastManagedDeviceIDKey)
                preferences.set(device.transport.rawValue, forKey: Self.lastManagedDeviceTransportKey)
                self.inspection = inspection
                inspectionsByConnection[inspection.device.connectionID] = inspection
                rememberName(of: inspection.device)
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
        // Choosing the Team must stay reachable while an interrupted setup
        // locks the phone, since a restart signs with the chosen Team.
        let teamChoice = destination == .environment(.selectTeam) && setup?.isBusy != true
        if setupLocksDevice && !teamChoice && destination != .startup && destination != activeOperationPage && destination != .environmentSummary {
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
        guard !busy, !restoringOperations, setup?.locksOtherDevices != true,
              let choice = availableConnections.first(where: { $0.id == id && (transport == nil || $0.transport == transport) }) else { return }
        if let pending = setup?.pendingTransaction, setup?.hasUnfinishedTransaction == true {
            // The unfinished phone keeps D14; another phone starts fresh.
            guard pending.deviceID != choice.id.lowercased() else { return }
            setup?.setAsideUnfinished()
            firstInstall = choice.transport == .usb
        }
        if selectedID?.lowercased() != id.lowercased() || selectedTransport != choice.transport {
            setup?.resetSelection()
        }
        selectedID = id; selectedTransport = choice.transport
        selectedDeviceSnapshot = choice
        preferences.set(choice.id.lowercased(), forKey: Self.lastManagedDeviceIDKey)
        preferences.set(choice.transport.rawValue, forKey: Self.lastManagedDeviceTransportKey)
        inspection = nil; failure = nil
    }

    /// A tap on a phone row. The phone holding an interrupted setup opens its
    /// D14 page; with no Team chosen the tap leads to the Team choice instead
    /// of doing nothing.
    public func openDevice(_ device: ConnectedDevice) {
        guard !busy else { return }
        if setup?.hasUnfinishedTransaction == true, setup?.pendingTransaction?.deviceID == device.id.lowercased() {
            openInterruptedSetup()
            return
        }
        select(device.id, transport: device.transport)
        if environment?.ready == true, selectedTeam == nil {
            navigate(.environment(.selectTeam))
            return
        }
        inspectSelected()
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
        savedIpa = value.ipa
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
        guard !busy, !restoringOperations, setup?.locksOtherDevices != true else { return }
        if setup?.hasUnfinishedTransaction == true {
            refreshDevicesAroundUnfinished()
            return
        }
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

    /// Rescan while D14 is shown. If the unfinished phone is still attached it
    /// keeps D14 and "Start over"; if it was swapped for another USB phone, the
    /// new phone is selected and inspected from scratch.
    private func refreshDevicesAroundUnfinished() {
        guard let pending = setup?.pendingTransaction else { return }
        perform(.devices) { data, request in
            let choices = ConnectedDevice.connectionChoices(
                try ResponseDecoder.decode(data, for: request, as: DeviceList.self).devices,
                usbOnly: false
            )
            self.devices = choices
            guard !choices.contains(where: { $0.id.lowercased() == pending.deviceID }) else { return }
            let candidates = ConnectedDevice.unique(choices, usbOnly: true)
            guard candidates.count == 1, let device = candidates.first else { return }
            self.setup?.setAsideUnfinished()
            self.firstInstall = true
            self.selectedID = device.id
            self.selectedTransport = device.transport
            self.selectedDeviceSnapshot = device
            self.inspection = nil
            self.route = .deviceDetail
            self.inspectAfterDeviceRefresh = true
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
            self.rememberName(of: result.device)
            self.route = .deviceDetail
        }
    }

    public func beginFirstInstall() {
        guard !busy, devicePageState == .readyToInstall,
              let device = selected, device.transport == .usb,
              let setup, setup.isRestored,
              let teamID = selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: teamID, allowProvisioningUpdates: true) else { return }
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
              let identity = setup.pendingTransaction else { return }
        // The interrupted transaction pins its Team. When Xcode no longer has
        // that account, the fresh transaction signs with the current Team.
        let pinnedTeamAvailable = environment.map { $0.teams.contains { $0.teamID == identity.teamID } } ?? true
        guard let teamID = pinnedTeamAvailable ? identity.teamID : selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: teamID, allowProvisioningUpdates: true) else { return }
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

    /// The saved IPA is newer than the phone's GoFly (version first, then build).
    public var projectIsNewer: Bool {
        GoFlyVersionOrder.isNewer(version: savedIpa?.version, build: savedIpa?.build,
                                  than: inspection?.appVersion, inspection?.appBuild) == true
    }

    /// Installing the saved IPA would downgrade the phone (§5.5 forbids it).
    public var savedIpaIsOlderThanInstalled: Bool {
        GoFlyVersionOrder.isNewer(version: inspection?.appVersion, build: inspection?.appBuild,
                                  than: savedIpa?.version, savedIpa?.build) == true
    }

    /// GitHub's newest signed IPA beats both the phone and the saved IPA.
    public var releaseIsNewer: Bool {
        guard let latestRelease, latestRelease.supported else { return false }
        let beatsPhone = GoFlyVersionOrder.isNewer(version: latestRelease.version, build: latestRelease.build,
                                                   than: inspection?.appVersion, inspection?.appBuild) == true
        let beatsSaved = savedIpa.map {
            GoFlyVersionOrder.isNewer(version: latestRelease.version, build: latestRelease.build,
                                      than: $0.version, $0.build) == true
        } ?? true
        return beatsPhone && beatsSaved
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
              let options = try? MacSetupOptions(teamID: team, allowProvisioningUpdates: true) else { return }
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

// MARK: - Saved IPA, GitHub Release and the IPA chooser (MAC-INSTALLER-SPEC §5.5)

extension MacAppModel {
    /// Query GitHub again every time; nothing about a release is built into the app.
    public func loadLatestRelease() {
        guard releaseLookup != .loading else { return }
        releaseLookup = .loading
        let request = CheckRequest.ipaRelease()
        releaseTask = Task {
            do {
                let data = try await live.check(request)
                let release = try ResponseDecoder.decode(data, for: request, as: IpaRelease.self)
                guard !Task.isCancelled else { return }
                self.latestRelease = release
                self.releaseLookup = .loaded
                if !self.ipaURLEdited || self.ipaURLText.isEmpty {
                    self.ipaURLText = release.ipaURL
                    self.ipaURLEdited = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.releaseLookup = .unavailable
            }
        }
    }

    /// Async variant for the 24-hour check; returns the release when one is found.
    @discardableResult
    public func refreshLatestRelease() async -> IpaRelease? {
        let request = CheckRequest.ipaRelease()
        guard let data = try? await live.check(request),
              let release = try? ResponseDecoder.decode(data, for: request, as: IpaRelease.self) else { return nil }
        latestRelease = release
        releaseLookup = .loaded
        if !ipaURLEdited || ipaURLText.isEmpty { ipaURLText = release.ipaURL; ipaURLEdited = false }
        return release
    }

    public func openIpaChooser() {
        guard !busy else { return }
        ipaChooserOpen = true
        ipaFailure = nil
        ipaURLEdited = false
        ipaURLText = latestRelease?.ipaURL ?? ""
        loadLatestRelease()
    }

    public func closeIpaChooser() {
        guard !ipaImportBusy else { return }
        ipaChooserOpen = false
        ipaFailure = nil
    }

    public var canCloseIpaChooser: Bool {
        ipaChooserOpen && savedIpa != nil && !savedIpaIsOlderThanInstalled && savedIpa?.supported != false
    }

    public func setIpaSourceMode(_ mode: IpaSourceMode) {
        guard !ipaImportBusy else { return }
        ipaSourceMode = mode
        ipaFailure = nil
    }

    /// D15b IPA field. Fills the signature from the same folder, else from GitHub.
    public func selectIpaFile(_ path: String) {
        guard !ipaImportBusy else { return }
        ipaFilePath = path
        ipaFailure = nil
        if signatureOrigin != .manual || signatureLocation == nil {
            signatureLocation = nil
            signatureOrigin = nil
        } else {
            return
        }
        let sibling = path + ".sig"
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: sibling, isDirectory: &isDirectory), !isDirectory.boolValue {
            signatureLocation = sibling
            signatureOrigin = .sameFolder
            return
        }
        let name = (path as NSString).lastPathComponent
        guard let range = name.range(of: #"^GoFly-GPS-([0-9]+(\.[0-9]+){0,3})\.ipa$"#, options: .regularExpression) else { return }
        let version = String(name[range].dropFirst("GoFly-GPS-".count).dropLast(".ipa".count))
        signatureLookupBusy = true
        let request = CheckRequest.ipaRelease(version: version)
        Task {
            defer { self.signatureLookupBusy = false }
            guard let data = try? await live.check(request),
                  let release = try? ResponseDecoder.decode(data, for: request, as: IpaRelease.self),
                  self.ipaFilePath == path, self.signatureLocation == nil else { return }
            self.signatureLocation = release.sigURL
            self.signatureOrigin = .github
        }
    }

    /// D15b signature field, chosen by hand.
    public func selectSignatureFile(_ path: String) {
        guard !ipaImportBusy else { return }
        signatureLocation = path
        signatureOrigin = .manual
        ipaFailure = nil
    }

    public var canImportIpa: Bool {
        guard !busy else { return false }
        switch ipaSourceMode {
        case .url:
            let text = ipaURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.hasPrefix("https://") && text.count <= 2048
        case .file:
            return ipaFilePath != nil && signatureLocation != nil
        }
    }

    /// The phone's GoFly, so a selection can never downgrade it.
    private var downgradeFloor: (version: String, build: String)? {
        guard inspection?.installed == true, let version = inspection?.appVersion,
              let build = inspection?.appBuild,
              GoFlyVersionOrder.key(version: version, build: build) != nil else { return nil }
        return (version, build)
    }

    public func importSelectedIpa() {
        guard canImportIpa else { return }
        let source: IpaImportSource
        switch ipaSourceMode {
        case .url:
            source = .url(ipa: ipaURLText.trimmingCharacters(in: .whitespacesAndNewlines),
                          sig: ipaURLText == latestRelease?.ipaURL ? latestRelease?.sigURL : nil)
        case .file:
            guard let ipa = ipaFilePath, let sig = signatureLocation else { return }
            source = .file(ipa: ipa, sig: sig)
        }
        runIpaImport(source)
    }

    /// D17 primary: download the newest release, then update and renew.
    public func downloadLatestAndUpdate() {
        guard !busy, let release = latestRelease, release.supported else { return }
        renewAfterImport = true
        runIpaImport(.url(ipa: release.ipaURL, sig: release.sigURL))
    }

    public func cancelIpaImport() {
        ipaTask?.cancel()
    }

    private func runIpaImport(_ source: IpaImportSource) {
        guard !ipaImportBusy else { return }
        ipaImportBusy = true
        ipaFailure = nil
        let request = CheckRequest.ipaImport(source, minimum: downgradeFloor)
        ipaTask = Task {
            defer { self.ipaImportBusy = false; self.ipaTask = nil }
            do {
                let data = try await live.check(request)
                let saved = try ResponseDecoder.decode(data, for: request, as: SavedIpa.self)
                self.savedIpa = saved
                self.ipaChooserOpen = false
                self.ipaFailure = nil
                self.ipaFilePath = nil
                self.signatureLocation = nil
                self.signatureOrigin = nil
                if self.renewAfterImport {
                    self.renewAfterImport = false
                    self.ipaImportBusy = false
                    self.startRenew()
                }
            } catch {
                self.renewAfterImport = false
                if Task.isCancelled || error is CancellationError || (error as? CheckFailure) == .cancelled {
                    self.ipaFailure = nil
                } else {
                    self.ipaFailure = error as? CheckFailure ?? .invalidResponse
                    // D16 is part of the chooser, even when a D17 download failed.
                    self.ipaChooserOpen = true
                }
            }
        }
    }
}
