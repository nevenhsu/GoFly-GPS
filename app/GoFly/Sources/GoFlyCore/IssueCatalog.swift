import Foundation

/// Where an error is owned. `app` is shown in every mode; `route` and
/// `joystick` only in their own mode; `data` belongs to the page that owns the
/// stored data and only raises the status pill.
public enum IssueScope: Equatable, Sendable {
    case app, route, joystick, data
}

/// `validation` errors are fixed by the person in place (pick a start, choose a
/// route) and never turn the status pill red.
public enum IssueKind: Equatable, Sendable {
    case blocking, validation
}

/// Toast actions are explicit so route planning repair stays separate from
/// connection retry, even though both appear in the same shared banner.
public enum IssueAction: String, Equatable, Sendable, CaseIterable {
    case retry, fix, settings, chooseFile

    public var localizationKey: String { "issue.action.\(rawValue)" }
}

public struct IssueInfo: Equatable, Sendable {
    public let scope: IssueScope
    public let kind: IssueKind
    public let action: IssueAction?
}

/// Classifies an error localization key. Keys are the catalog codes in
/// docs/IOS-ERROR-TOAST-COPY.md.
public enum IssueCatalog {
    private static let settingsKeys: Set<String> = [
        DeviceServiceFailure.pairingRequired.rawValue,
        DeviceServiceFailure.identityMismatch.rawValue,
        DeviceServiceFailure.developerModeRequired.rawValue,
        DeviceServiceFailure.devicePreparationRequired.rawValue,
        DeviceServiceFailure.storageUnavailable.rawValue,
    ]
    private static let retryKeys: Set<String> = [
        DeviceServiceFailure.serviceUnavailable.rawValue,
        DeviceServiceFailure.tunnelUnavailable.rawValue,
        DeviceServiceFailure.operationTimedOut.rawValue,
        "joystick.error.noCandidate",
    ]
    private static let fixKeys: Set<String> = [
        "route.error.planningFailed",
    ]
    private static let chooseFileKeys: Set<String> = [
        "imports.error.unsafeFile", "imports.error.invalidFilename",
        "imports.error.metadataMismatch", "imports.error.hashMismatch",
    ]
    private static let validationKeys: Set<String> = [
        "route.error.missingStart", "route.error.missingDestination",
        "route.error.currentLocationUnavailable",
    ]
    private static let validationSuffixes = [".invalidLabel", ".noSelection", ".busy", ".nothingToUndo"]

    public static func info(for key: String) -> IssueInfo {
        IssueInfo(scope: scope(of: key), kind: kind(of: key), action: action(for: key))
    }

    public static func isValidation(_ key: String) -> Bool { kind(of: key) == .validation }

    private static func scope(of key: String) -> IssueScope {
        if key.hasPrefix("route.error.") || key.hasPrefix("imports.execution.") { return .route }
        if key.hasPrefix("joystick.error.") || key.hasPrefix("wander.") { return .joystick }
        if key.hasPrefix("favorites.error.") || key.hasPrefix("imports.error.")
            || key.hasPrefix("favoriteRoutes.error.") || key.hasPrefix("gpx.error.")
            || key.hasPrefix("recovery.error.") { return .data }
        return .app
    }

    private static func kind(of key: String) -> IssueKind {
        validationKeys.contains(key) || validationSuffixes.contains { key.hasSuffix($0) }
            ? .validation : .blocking
    }

    private static func action(for key: String) -> IssueAction? {
        if kind(of: key) == .validation { return nil }
        if settingsKeys.contains(key) { return .settings }
        if fixKeys.contains(key) { return .fix }
        if retryKeys.contains(key) { return .retry }
        if chooseFileKeys.contains(key) || key.hasPrefix("gpx.error.") { return .chooseFile }
        if scope(of: key) == .data, key.hasSuffix(".unavailable") || key.hasSuffix(".writeFailed") {
            return .retry
        }
        return nil
    }
}
