import Combine
import Foundation
import Network
import UIKit

/// Manages Wi-Fi connection state and synchronization across the map and settings.
@MainActor
final class GoFlyNetworkMonitor: ObservableObject {
    static let shared = GoFlyNetworkMonitor()

    @Published private(set) var isWiFiConnected: Bool = true

    private let paths = GoFlyPathMonitor.shared
    private var subscription: AnyCancellable?

    private init() {
        start()
    }

    func start() {
        guard subscription == nil else { return }
#if DEBUG && targetEnvironment(simulator)
        if GoFlyUITestOverrides.isFrameMode {
            isWiFiConnected = !GoFlyUITestOverrides.contains("-gofly-ui-wifi-disconnected")
            return
        }
#endif
        paths.start()
        isWiFiConnected = Self.evaluate(paths.currentPath)
        subscription = paths.changes.sink { [weak self] path in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isWiFiConnected = Self.evaluate(path)
            }
        }
    }

    private nonisolated static func evaluate(_ path: NWPath) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-wifi-disconnected") {
            return false
        } else if ProcessInfo.processInfo.arguments.contains("-gofly-ui-wifi-connected") {
            return true
        } else {
            return path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
        }
#else
        return path.status == .satisfied && path.usesInterfaceType(.wifi)
#endif
    }

    func openWiFiSettings() {
        let candidates = [
            "App-Prefs:root=WIFI",
            "App-prefs:root=WIFI",
            "prefs:root=WIFI"
        ]
        func tryCandidate(at index: Int) {
            guard index < candidates.count else {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                }
                return
            }
            if let url = URL(string: candidates[index]) {
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened {
                        tryCandidate(at: index + 1)
                    }
                }
            } else {
                tryCandidate(at: index + 1)
            }
        }
        tryCandidate(at: 0)
    }
}
