import GoFlyCore
import SwiftUI
import UIKit

/// The one error toast for a `ConnectionIssue`, shared by onboarding (R04.a),
/// the VPN settings page and the map. Its button fixes the issue where iOS
/// allows it: Wi-Fi settings, GoFly's page in Settings, or LocalDevVPN.
struct GoFlyConnectionIssueBanner: View {
    let issue: ConnectionIssue
    /// The toast's identifier; the button is `<identifier>.<issue suffix>`.
    let identifier: String
    /// Extra lines under the message, such as what iOS reported.
    var detail: String? = nil
    var titleIdentifier: String? = nil
    var onDismiss: (() -> Void)? = nil
    var isFloating = true
    /// Called with the localization key of the failure when the target cannot be opened.
    var onOpenFailed: (String) -> Void = { _ in }

    var body: some View {
        GoFlyStatusBanner(tone: .danger,
                          title: goFlyString(issue.titleKey),
                          message: [goFlyString(issue.messageKey), detail].compactMap { $0 }.joined(separator: "\n"),
                          actionTitle: goFlyString(issue.actionTitleKey),
                          onAction: { goFlyResolve(issue, onOpenFailed: onOpenFailed) },
                          onDismiss: onDismiss,
                          identifier: identifier,
                          actionIdentifier: "\(identifier).\(issue.identifierSuffix)",
                          titleIdentifier: titleIdentifier,
                          isFloating: isFloating)
    }
}

/// Opens the place that fixes `issue`.
@MainActor
func goFlyResolve(_ issue: ConnectionIssue, onOpenFailed: @escaping (String) -> Void = { _ in }) {
    switch issue {
    case .wifiNotConnected:
        GoFlyNetworkMonitor.shared.openWiFiSettings()
    case .localNetworkNotAllowed:
        // iOS asks for Local Network only once; afterwards the switch lives in Settings.
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            onOpenFailed("settings.externalOpenFailed")
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            Task { @MainActor in if !opened { onOpenFailed("settings.externalOpenFailed") } }
        }
    case .vpnNotConnected:
        GoFlyExternalLinks.openLocalDevVPN { opened in
            if !opened { onOpenFailed("onboarding.vpn.externalOpenFailed") }
        }
    }
}
