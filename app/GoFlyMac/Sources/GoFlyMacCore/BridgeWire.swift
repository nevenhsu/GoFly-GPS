import Foundation

/// Foundation decodes values; this bounded preflight rejects duplicate keys
/// (including escaped spellings) and a coerced protocol/journal version.
enum SetupWireJSON {
    static func object(_ data: Data, integerKey: String? = nil, integerValue: String? = nil,
                       maximumBytes: Int = 262_144) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MacSetupFailure.invalidResponse }
        var scan = Scan(bytes: Array(data), integerKey: integerKey, integerValue: integerValue)
        _ = try scan.value(depth: 0)
        scan.whitespace()
        guard scan.index == scan.bytes.count, (integerKey == nil || scan.foundInteger),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MacSetupFailure.invalidResponse
        }
        return object
    }

    private struct Scan {
        let bytes: [UInt8]
        let integerKey: String?
        let integerValue: String?
        var index = 0
        var foundInteger = false

        mutating func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> String? {
            guard depth <= 64 else { throw MacSetupFailure.invalidResponse }
            whitespace()
            guard index < bytes.count else { throw MacSetupFailure.invalidResponse }
            switch bytes[index] {
            case 123:
                index += 1
                var names = Set<String>()
                if take(125) { return nil }
                while true {
                    let name = try string()
                    guard names.insert(name).inserted, take(58) else { throw MacSetupFailure.invalidResponse }
                    let literal = try value(depth: depth + 1)
                    if depth == 0, name == integerKey {
                        guard literal == integerValue else { throw MacSetupFailure.invalidResponse }
                        foundInteger = true
                    }
                    if take(125) { return nil }
                    guard take(44) else { throw MacSetupFailure.invalidResponse }
                }
            case 91:
                index += 1
                if take(93) { return nil }
                while true {
                    _ = try value(depth: depth + 1)
                    if take(93) { return nil }
                    guard take(44) else { throw MacSetupFailure.invalidResponse }
                }
            case 34:
                _ = try string()
                return nil
            default:
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw MacSetupFailure.invalidResponse }
                return String(decoding: bytes[start..<index], as: UTF8.self)
            }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func string() throws -> String {
            whitespace()
            let start = index
            guard index < bytes.count, bytes[index] == 34 else { throw MacSetupFailure.invalidResponse }
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 92 {
                    guard index < bytes.count else { throw MacSetupFailure.invalidResponse }
                    index += 1
                } else if byte == 34 {
                    guard let result = try JSONSerialization.jsonObject(
                        with: Data(bytes[start..<index]), options: .fragmentsAllowed
                    ) as? String else { throw MacSetupFailure.invalidResponse }
                    return result
                }
            }
            throw MacSetupFailure.invalidResponse
        }
    }
}
import Foundation

/// Live requests are deliberately a closed, read-only set.
public enum CheckAction: String, Codable, Sendable { case environment, devices, inspect, registeredDevices }

public enum MacBundleIdentifier {
    private static let prefix = "com.neven.gofly."

    public static func forTeamID(_ teamID: String) -> String? {
        guard setupFullMatch(teamID, "^[A-Z0-9]{10}$") else { return nil }
        return prefix + teamID.lowercased()
    }

    public static func isGoFly(_ value: String) -> Bool {
        setupFullMatch(value, "^com\\.neven\\.gofly\\.[a-z0-9]{10}$")
    }
}

public struct CheckRequest: Codable, Sendable {
    public let requestID: String
    public let action: CheckAction
    public let deviceID: String?
    public let transport: ConnectedDevice.Transport?
    public let teamID: String?

    public init(action: CheckAction, deviceID: String? = nil, transport: ConnectedDevice.Transport? = nil,
                teamID: String? = nil) {
        self.requestID = UUID().uuidString
        self.action = action
        self.deviceID = deviceID
        self.transport = action == .inspect ? transport : nil
        self.teamID = action == .inspect || action == .registeredDevices ? teamID : nil
    }
}

public enum EnvironmentCheckStatus: String, Codable, Sendable { case passed, failed, unknown }

public struct EnvironmentCheck: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let passed: Bool
    public let status: EnvironmentCheckStatus?
    public init(id: String, title: String, detail: String, passed: Bool,
                status: EnvironmentCheckStatus? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.passed = passed; self.status = status
    }
}

public struct MacTeam: Codable, Identifiable, Equatable, Sendable {
    public let teamID: String
    public let teamName: String
    public let isFreeProvisioningTeam: Bool
    public var id: String { teamID }
    public init(teamID: String, teamName: String, isFreeProvisioningTeam: Bool) {
        self.teamID = teamID; self.teamName = teamName; self.isFreeProvisioningTeam = isFreeProvisioningTeam
    }
}

public struct MacEnvironment: Codable, Equatable, Sendable {
    public let ready: Bool
    public let checks: [EnvironmentCheck]
    public let teams: [MacTeam]
    public let xcodeVersion: String?
    public let projectVersion: String?
    public let projectBuild: String?
    public init(ready: Bool, checks: [EnvironmentCheck], teams: [MacTeam] = [],
                xcodeVersion: String? = nil, projectVersion: String? = nil, projectBuild: String? = nil) {
        self.ready = ready; self.checks = checks; self.teams = teams
        self.xcodeVersion = xcodeVersion; self.projectVersion = projectVersion; self.projectBuild = projectBuild
    }

    private enum CodingKeys: String, CodingKey { case ready, checks, teams, xcodeVersion, projectVersion, projectBuild }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ready = try values.decode(Bool.self, forKey: .ready)
        checks = try values.decode([EnvironmentCheck].self, forKey: .checks)
        teams = try values.decodeIfPresent([MacTeam].self, forKey: .teams) ?? []
        xcodeVersion = try values.decodeIfPresent(String.self, forKey: .xcodeVersion)
        projectVersion = try values.decodeIfPresent(String.self, forKey: .projectVersion)
        projectBuild = try values.decodeIfPresent(String.self, forKey: .projectBuild)
    }
}

public struct ConnectedDevice: Codable, Identifiable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable { case usb, wifi }
    public let id: String
    public let name: String
    public let modelName: String?
    public let transport: Transport
    public let osVersion: String?
    public init(id: String, name: String, transport: Transport, osVersion: String? = nil, modelName: String? = nil) {
        self.id = id; self.name = name; self.modelName = modelName
        self.transport = transport; self.osVersion = osVersion
    }
    public var connectionName: String { transport == .usb ? "USB" : "Wi-Fi" }
    public var displayName: String { name.isEmpty ? "iPhone · …\(id.suffix(6))" : name }
    public var connectionID: String { id.lowercased() + ":" + transport.rawValue }

    /// Keeps both explicit connection choices for the same phone.
    /// First install continues to use the USB-only list.
    public static func connectionChoices(_ devices: [Self], usbOnly: Bool) -> [Self] {
        var choices: [String: Self] = [:]
        for device in devices where !usbOnly || device.transport == .usb {
            if choices[device.connectionID] == nil { choices[device.connectionID] = device }
        }
        return choices.values.sorted {
            ($0.name, $0.id.lowercased(), $0.transport == .usb ? 0 : 1) <
            ($1.name, $1.id.lowercased(), $1.transport == .usb ? 0 : 1)
        }
    }

    public static func unique(_ devices: [Self], usbOnly: Bool) -> [Self] {
        var byID: [String: Self] = [:]
        for device in devices where !usbOnly || device.transport == .usb {
            let key = device.id.lowercased()
            if byID[key] == nil || device.transport == .usb { byID[key] = device }
        }
        return byID.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

public struct DeviceInspection: Codable, Equatable, Sendable {
    public let device: ConnectedDevice
    public let developerMode: Bool?
    public let installed: Bool?
    public let vpnInstalled: Bool?
    public let appVersion: String?
    public let appBuild: String?
    public let teamID: String?
    public let expiresAt: String?
    public init(device: ConnectedDevice, developerMode: Bool?, installed: Bool?, vpnInstalled: Bool?,
                appVersion: String? = nil, appBuild: String? = nil, teamID: String? = nil, expiresAt: String? = nil) {
        self.device = device; self.developerMode = developerMode; self.installed = installed
        self.vpnInstalled = vpnInstalled; self.appVersion = appVersion; self.appBuild = appBuild
        self.teamID = teamID; self.expiresAt = expiresAt
    }
}

public struct DeviceList: Codable, Sendable { public let devices: [ConnectedDevice] }

/// A phone holding one of the Team's registration slots, read from the
/// Team's local provisioning profiles. The name is empty when unknown.
public struct RegisteredDevice: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct RegisteredDeviceList: Codable, Sendable { public let devices: [RegisteredDevice] }

public enum CheckFailure: Error, Equatable, Sendable {
    case bundleInvalid, unavailable, invalidResponse, timeout, cancelled, service(String)

    public var title: String {
        switch self {
        case .cancelled: "檢查已取消"
        case .timeout: "檢查逾時"
        case .bundleInvalid: "GoFly 無法啟動，請重新安裝"
        case .unavailable: "GoFly 無法啟動，請重新安裝"
        case .invalidResponse: "無法確認檢查結果"
        case .service(let code):
            switch code {
            case "trust-required", "usb-lockdown-failed": "請在 iPhone 完成信任"
            case "developer-mode-required": "請啟用 iPhone 開發者模式"
            case "device-disconnected", "usb-device-not-found": "iPhone 連線已中斷"
            case "identity-mismatch", "device-identity-mismatch": "目前連接的 iPhone 不符"
            case "unsupported-os", "unsupported-os-version": "目前 iOS 版本不在檢查範圍"
            case "environment-not-ready": "Mac 環境尚未就緒"
            case "bundle-damaged": "GoFly 無法啟動，請重新安裝"
            default: "尚未確認檢查成功"
            }
        }
    }
    public var detail: String {
        switch self {
        case .bundleInvalid: ""
        case .unavailable: ""
        case .timeout: "沒有取得完整回覆。請確認連線與手機解鎖狀態，再手動重新檢查。"
        case .cancelled: "這次唯讀檢查已結束，可重新選擇裝置或再檢查。"
        case .invalidResponse: "回覆未通過格式或裝置身分核對，先前狀態已作廢。請重新檢查。"
        case .service(let code):
            switch code {
            case "trust-required", "usb-lockdown-failed": "解鎖 iPhone，確認已信任這部 Mac，再按重新檢查。本版不會自動建立配對。"
            case "bundle-damaged": ""
            case "developer-mode-required": "在 iPhone「設定 → 隱私權與安全性 → 開發者模式」手動完成設定後，再重新檢查。"
            case "device-disconnected", "usb-device-not-found": "請重新連接原 iPhone，再回到裝置清單。檢查不會自動切換到其他手機。"
            case "unsupported-os", "unsupported-os-version": "現有檢查介面以 iOS 26 以上為目標；這不代表各版本已通過實機驗收。"
            default: "請確認 Xcode、裝置連接與信任狀態，再重新檢查。這次沒有安裝 App 或寫入裝置。"
            }
        }
    }
}

public protocol MacChecking: Sendable {
    func check(_ request: CheckRequest) async throws -> Data
}

public enum ResponseDecoder {
    private struct Envelope: Decodable {
        let requestID: String
        let status: String
        let code: String?
    }
    private struct Result<T: Decodable>: Decodable { let payload: T }

    public static func decode<T: Decodable>(_ data: Data, for request: CheckRequest, as type: T.Type) throws -> T {
        guard !data.isEmpty, data.count <= 262_144 else { throw CheckFailure.invalidResponse }
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.requestID == request.requestID,
                  ["ok", "error"].contains(envelope.status) else { throw CheckFailure.invalidResponse }
            if envelope.status == "error" {
                let safeCodes: Set<String> = ["invalid-request", "protocol-mismatch", "bundle-damaged", "environment-not-ready",
                    "device-disconnected", "trust-required", "developer-mode-required", "unsupported-os", "identity-mismatch",
                    "signing-required", "operation-failed", "busy", "usb-lockdown-failed", "usb-device-not-found",
                    "device-identity-mismatch", "unsupported-os-version", "runtime-unavailable", "dependency-mismatch",
                    "device-values-unavailable", "runtime-api-mismatch", "timeout", "configuration-invalid",
                    "invalid-config"]
                guard let code = envelope.code, safeCodes.contains(code) else { throw CheckFailure.invalidResponse }
                throw CheckFailure.service(code)
            }
            return try decoder.decode(Result<T>.self, from: data).payload
        } catch let error as CheckFailure { throw error }
        catch { throw CheckFailure.invalidResponse }
    }
}
import Foundation
import CoreFoundation

func setupFullMatch(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
}

public enum MacSetupAction: String, Codable, Sendable { case preflight, apply, status }
public enum MacSetupMode: String, Codable, Sendable { case install, renew }

public enum MacSetupFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, unavailable, cancelled, timeout
    case service(String)
}

public struct MacSetupOptions: Codable, Equatable, Sendable {
    public let teamID: String
    public let allowProvisioningUpdates: Bool

    public init(teamID: String, allowProvisioningUpdates: Bool = false) throws {
        guard setupFullMatch(teamID, "^[A-Z0-9]{10}$") else {
            throw MacSetupFailure.invalidRequest
        }
        self.teamID = teamID
        self.allowProvisioningUpdates = allowProvisioningUpdates
    }

    private enum CodingKeys: String, CodingKey { case teamID, allowProvisioningUpdates }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(teamID: values.decode(String.self, forKey: .teamID),
                      allowProvisioningUpdates: values.decode(Bool.self, forKey: .allowProvisioningUpdates))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(teamID, forKey: .teamID)
        try values.encode(allowProvisioningUpdates, forKey: .allowProvisioningUpdates)
    }
}

public struct MacSetupRequest: Encodable, Sendable {
    public let requestID: UUID
    public let setupID: UUID?
    public let deviceID: String?
    public let mode: MacSetupMode?
    public let transport: ConnectedDevice.Transport?
    public let action: MacSetupAction
    public let options: MacSetupOptions?
    public let teamID: String?

    public init(action: MacSetupAction, requestID: UUID = UUID(), setupID: UUID? = nil, deviceID: String? = nil,
                mode: MacSetupMode? = nil, transport: ConnectedDevice.Transport? = nil,
                options: MacSetupOptions? = nil, teamID: String? = nil) throws {
        let normalized = deviceID?.lowercased()
        if let normalized {
            guard setupFullMatch(normalized, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$") else {
                throw MacSetupFailure.invalidRequest
            }
        }
        let resolvedMode: MacSetupMode?
        if let options, let teamID, options.teamID != teamID {
            throw MacSetupFailure.invalidRequest
        }
        let resolvedTeamID = options?.teamID ?? teamID
        if action == .status, setupID == nil, deviceID == nil, mode == nil {
            guard resolvedTeamID == nil else { throw MacSetupFailure.invalidRequest }
            resolvedMode = nil
        } else if setupID == nil || normalized == nil {
            throw MacSetupFailure.invalidRequest
        } else {
            resolvedMode = mode ?? .install
        }
        let resolvedTransport = setupID == nil ? nil : (transport ?? .usb)
        guard resolvedMode != .install || resolvedTransport == .usb else {
            throw MacSetupFailure.invalidRequest
        }
        guard ((action == .preflight || action == .apply) == (options != nil)) else {
            throw MacSetupFailure.invalidRequest
        }
        if setupID != nil {
            guard let resolvedTeamID, MacBundleIdentifier.forTeamID(resolvedTeamID) != nil else {
                throw MacSetupFailure.invalidRequest
            }
        }
        self.requestID = requestID
        self.setupID = setupID
        self.deviceID = normalized
        self.mode = resolvedMode
        self.transport = resolvedTransport
        self.action = action
        self.options = options
        self.teamID = resolvedTeamID
    }
}

public enum MacSetupStage: String, Decodable, Sendable {
    case preflight, artifact, pairing, install, support, handoff, complete
}
public enum MacSetupOutcome: String, Decodable, Sendable {
    case ready, inProgress, confirmed, unknown, failed
}

public struct MacSetupSnapshot: Equatable, Sendable {
    public let mode: MacSetupMode
    public let stage: MacSetupStage
    public let outcome: MacSetupOutcome
    public let appBuild: String?
    public let teamID: String?
    public let expiresAt: String?
    public let receiptSHA256: String?
    public let installationConfirmed: Bool
    public let pairingImported: Bool
    public let supportObserved: Bool
    public let errorCode: String?

    public init(mode: MacSetupMode, stage: MacSetupStage, outcome: MacSetupOutcome,
                appBuild: String?, teamID: String?, expiresAt: String?, receiptSHA256: String?,
                installationConfirmed: Bool, pairingImported: Bool, supportObserved: Bool,
                errorCode: String?) {
        self.mode = mode
        self.stage = stage
        self.outcome = outcome
        self.appBuild = appBuild
        self.teamID = teamID
        self.expiresAt = expiresAt
        self.receiptSHA256 = receiptSHA256
        self.installationConfirmed = installationConfirmed
        self.pairingImported = pairingImported
        self.supportObserved = supportObserved
        self.errorCode = errorCode
    }

    public var failure: MacSetupFailure? { errorCode.map(MacSetupFailure.service) }

    /// A legacy signed-only renew may be replaced, but is not device-ready.
    public var canReplaceCompletedTransaction: Bool {
        isComplete || (mode == .renew && stage == .complete && outcome == .confirmed &&
            installationConfirmed && !pairingImported && !supportObserved &&
            receiptSHA256 != nil && appBuild != nil && errorCode == nil)
    }

    public var isComplete: Bool {
        let imported = pairingImported && supportObserved
        return stage == .complete && outcome == .confirmed && installationConfirmed &&
            imported && receiptSHA256 != nil && appBuild != nil && errorCode == nil
    }
}

public protocol MacSetupRunning: Sendable {
    func run(_ request: MacSetupRequest) async throws -> Data
}

public enum MacSetupResponseDecoder {
    public static func probe(_ data: Data) throws -> (MacSetupTransactionIdentity, MacSetupSnapshot) {
        do {
            let root = try SetupWireJSON.object(data)
            guard let rawRequestID = root["requestID"] as? String, rawRequestID.utf8.count == 36,
                  let requestID = UUID(uuidString: rawRequestID),
                  let rawID = root["setupID"] as? String, rawID.utf8.count == 36,
                  let id = UUID(uuidString: rawID),
                  let device = root["deviceID"] as? String, device == device.lowercased(),
                  let rawMode = root["mode"] as? String, let mode = MacSetupMode(rawValue: rawMode),
                  let teamID = (root["payload"] as? [String: Any])?["teamID"] as? String else {
                throw MacSetupFailure.invalidResponse
            }
            guard let transport = ConnectedDevice.Transport(rawValue: root["transport"] as? String ?? "usb") else {
                throw MacSetupFailure.invalidResponse
            }
            let request = try MacSetupRequest(action: .status, requestID: requestID, setupID: id, deviceID: device,
                                              mode: mode, transport: transport, teamID: teamID)
            let snapshot = try decode(data, for: request)
            return (try MacSetupTransactionIdentity(setupID: id, deviceID: device, mode: mode,
                                                     transport: transport, teamID: teamID), snapshot)
        } catch let error as MacSetupFailure { throw error }
        catch { throw MacSetupFailure.invalidResponse }
    }

    private static let safeCodes: Set<String> = [
        "invalid-request", "protocol-mismatch", "configuration-invalid", "dependency-mismatch",
        "runtime-api-mismatch", "environment-not-ready", "device-disconnected", "wifi-device-not-found",
        "wifi-pairing-unknown", "wifi-support-unavailable", "wifi-renew-unknown", "trust-required",
        "developer-mode-required", "unsupported-os", "identity-mismatch", "app-already-installed", "app-not-installed", "app-running",
        "signing-required", "signature-invalid", "artifact-mismatch", "support-unavailable",
        "pairing-unknown", "pairing-rejected", "handoff-unknown", "commit-unknown",
        "transaction-unknown", "transaction-conflict", "busy", "cancelled", "timeout",
        "storage-unavailable", "operation-failed", "device-limit-reached", "developer-untrusted"
    ]

    public static func decode(_ data: Data, for request: MacSetupRequest) throws -> MacSetupSnapshot {
        do {
            let root = try SetupWireJSON.object(data)
            guard keys(root, required: ["action", "requestID", "setupID", "deviceID", "status"], optional: ["payload", "code", "mode", "transport"]),
                  root["action"] as? String == request.action.rawValue,
                  uuid(root["requestID"]) == request.requestID,
                  uuid(root["setupID"]) == request.setupID,
                  root["deviceID"] as? String == request.deviceID,
                  ((root["transport"] as? String).map { $0 == request.transport?.rawValue }
                    ?? (request.transport == nil || request.transport == .usb)),
                  let status = root["status"] as? String, ["ok", "error"].contains(status),
                  let payload = root["payload"] as? [String: Any],
                  keys(payload, required: ["stage", "outcome", "proof"],
                       optional: ["app", "teamID", "expiresAt", "receiptSHA256"]),
                  let stage = (payload["stage"] as? String).flatMap(MacSetupStage.init(rawValue:)),
                  let outcome = (payload["outcome"] as? String).flatMap(MacSetupOutcome.init(rawValue:)),
                  let proof = payload["proof"] as? [String: Any],
                  keys(proof, required: ["installationConfirmed", "pairingImported", "supportObserved"]),
                  let installed = boolean(proof["installationConfirmed"]),
                  let paired = boolean(proof["pairingImported"]),
                  let support = boolean(proof["supportObserved"]) else { throw MacSetupFailure.invalidResponse }
            let code: String?
            if status == "error" {
                guard let value = root["code"] as? String, safeCodes.contains(value) else {
                    throw MacSetupFailure.invalidResponse
                }
                code = value
            } else {
                guard root["code"] == nil else { throw MacSetupFailure.invalidResponse }
                code = nil
            }
            let team = try optionalString(payload["teamID"])
            let expiry = try optionalString(payload["expiresAt"])
            let receipt = try optionalString(payload["receiptSHA256"])
            if let team, !setupFullMatch(team, "^[A-Z0-9]{10}$") {
                throw MacSetupFailure.invalidResponse
            }
            if let expiry, !validDate(expiry) { throw MacSetupFailure.invalidResponse }
            if let receipt, !hash(receipt) { throw MacSetupFailure.invalidResponse }
            let build: String?
            if let raw = payload["app"], !(raw is NSNull) {
                guard let app = raw as? [String: Any],
                      keys(app, required: ["bundleID", "build", "profileSHA256", "executableSHA256"]),
                      let bundleID = app["bundleID"] as? String,
                      MacBundleIdentifier.forTeamID(team ?? "") == bundleID,
                      let value = app["build"] as? String, !value.isEmpty, value.utf8.count <= 128,
                      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      let profile = app["profileSHA256"] as? String, hash(profile),
                      let executable = app["executableSHA256"] as? String, hash(executable) else {
                    throw MacSetupFailure.invalidResponse
                }
                build = value
            } else { build = nil }
            if let requestedTeam = request.teamID, requestedTeam != team {
                throw MacSetupFailure.invalidResponse
            }
            if stage == .preflight, installed || paired || support { throw MacSetupFailure.invalidResponse }
            if request.action == .preflight, stage != .preflight { throw MacSetupFailure.invalidResponse }
            if stage == .complete, outcome == .confirmed {
                let mode = request.mode ?? .install
                let imported = mode == .renew || (paired && support)
                guard installed, imported, receipt != nil, build != nil, team != nil else {
                    throw MacSetupFailure.invalidResponse
                }
            }
            return MacSetupSnapshot(mode: request.mode ?? .install, stage: stage, outcome: outcome,
                                    appBuild: build, teamID: team, expiresAt: expiry, receiptSHA256: receipt,
                                    installationConfirmed: installed, pairingImported: paired,
                                    supportObserved: support, errorCode: code)
        } catch { throw MacSetupFailure.invalidResponse }
    }

    private static func keys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) -> Bool {
        required.isSubset(of: Set(object.keys)) && Set(object.keys).isSubset(of: required.union(optional))
    }
    private static func uuid(_ value: Any?) -> UUID? {
        guard let string = value as? String, string.utf8.count == 36 else { return nil }
        return UUID(uuidString: string)
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func hash(_ value: String) -> Bool {
        setupFullMatch(value, "^[0-9a-f]{64}$")
    }
    private static func optionalString(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw MacSetupFailure.invalidResponse }
        return string
    }
    private static func validDate(_ value: String) -> Bool {
        guard value.utf8.count <= 40, value.hasSuffix("Z") else { return false }
        let parser = ISO8601DateFormatter()
        if parser.date(from: value) != nil { return true }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: value) != nil
    }
}
