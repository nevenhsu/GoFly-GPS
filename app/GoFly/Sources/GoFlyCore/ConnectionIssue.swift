import Foundation

/// The connection errors every connection check reports, in the order a person
/// fixes them: Wi-Fi first, then the Local Network permission, then the
/// LocalDevVPN tunnel. Onboarding (R04.a), the VPN settings page and the map
/// show only the first one that applies.
public enum ConnectionIssue: Equatable, Sendable {
    /// Button: Settings, opens the iPhone Settings app.
    case wifiNotConnected
    /// Button: Settings, opens GoFly's page in the Settings app.
    case localNetworkNotAllowed
    /// Button: Connect, opens the LocalDevVPN app.
    case vpnNotConnected

    /// - Parameters:
    ///   - checkFailed: the last tunnel check failed or timed out.
    ///   - localNetworkDenied: the system reported the permission as off. A failed
    ///     check alone never implies it; the device service may just be unreachable.
    public static func first(isWiFiConnected: Bool, checkFailed: Bool,
                             localNetworkDenied: Bool) -> ConnectionIssue? {
        if !isWiFiConnected { return .wifiNotConnected }
        guard checkFailed else { return nil }
        return localNetworkDenied ? .localNetworkNotAllowed : .vpnNotConnected
    }

    public var titleKey: String {
        switch self {
        case .wifiNotConnected: "connection.wifi.title"
        case .localNetworkNotAllowed: "connection.localNetwork.title"
        case .vpnNotConnected: "connection.vpn.title"
        }
    }

    public var messageKey: String {
        switch self {
        case .wifiNotConnected: "connection.wifi.message"
        case .localNetworkNotAllowed: "connection.localNetwork.message"
        case .vpnNotConnected: "connection.vpn.message"
        }
    }

    public var actionTitleKey: String {
        switch self {
        case .wifiNotConnected, .localNetworkNotAllowed: "operation.settings"
        case .vpnNotConnected: "connection.connect"
        }
    }

    /// Suffix for accessibility identifiers, e.g. `onboarding.vpn.failure.wifi`.
    public var identifierSuffix: String {
        switch self {
        case .wifiNotConnected: "wifi"
        case .localNetworkNotAllowed: "localNetwork"
        case .vpnNotConnected: "vpn"
        }
    }
}
