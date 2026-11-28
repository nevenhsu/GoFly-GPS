import UIKit

enum GoFlyLiveContainerHost {
    /// LiveContainer hooks both `Bundle.main` and `_NSGetExecutablePath` to
    /// spoof the guest app bundle, while preserving the real host container
    /// bundle on `+[NSUserDefaults lcMainBundle]`.
    nonisolated static func hostBundle() -> Bundle? {
        let selector = NSSelectorFromString("lcMainBundle")
        guard UserDefaults.responds(to: selector) else { return nil }
        guard let bundle = UserDefaults.perform(selector)?.takeUnretainedValue() as? Bundle,
              bundle.bundleURL != Bundle.main.bundleURL else {
            return nil
        }
        return bundle
    }

    /// Real bundle identifier of the hosting LiveContainer app, or `nil` when
    /// running as a normal standalone install.
    nonisolated static var hostBundleIdentifier: String? {
        guard let hostID = hostBundle()?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hostID.isEmpty else {
            return nil
        }
        return hostID
    }

    /// True when running inside LiveContainer with a spoofed guest bundle ID
    /// (i.e. "Use LiveContainer's Bundle ID" is off).
    nonisolated static var usesSpoofedBundleIdentifier: Bool {
        guard let hostID = hostBundleIdentifier else { return false }
        return hostID != Bundle.main.bundleIdentifier
    }

    /// Display name of the hosting container (e.g. "LiveContainer" or
    /// "LiveContainer2"), or `nil` when running as a standalone install.
    nonisolated static var hostDisplayName: String? {
        guard let bundle = hostBundle() else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : "LiveContainer"
    }
}

@MainActor
enum GoFlyExternalLinks {
    static func openLocalDevVPN(completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(URL(string: "localdevvpn://")!, options: [:]) { accepted in
            Task { @MainActor in
                if accepted { completion(true) } else { openStore(completion: completion) }
            }
        }
    }

    static func openStore(completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!, options: [:]) { accepted in
            Task { @MainActor in completion(accepted) }
        }
    }

    /// Opens the Settings page for the app identity that owns system permissions.
    /// Inside LiveContainer, `Bundle.main` is spoofed to the guest app, so plain
    /// `openSettingsURLString` can land on a standalone GoFly install or the root
    /// Settings screen; try targeting the real LiveContainer host bundle ID first.
    static func openAppSettings(completion: @escaping @MainActor (Bool) -> Void) {
        let candidates = appSettingsCandidateURLs()
        guard !candidates.isEmpty else { return completion(false) }

        func tryCandidate(at index: Int) {
            guard index < candidates.count else { return completion(false) }
            UIApplication.shared.open(candidates[index], options: [:]) { accepted in
                Task { @MainActor in
                    if accepted {
                        completion(true)
                    } else {
                        tryCandidate(at: index + 1)
                    }
                }
            }
        }

        tryCandidate(at: 0)
    }

    private static func appSettingsCandidateURLs() -> [URL] {
        var rawStrings: [String] = []
        if let hostID = GoFlyLiveContainerHost.hostBundleIdentifier,
           hostID != Bundle.main.bundleIdentifier {
            rawStrings.append("App-Prefs:\(hostID)")
            rawStrings.append("App-Prefs:root=\(hostID)")
            rawStrings.append("app-settings:\(hostID)")
        }
        rawStrings.append(UIApplication.openSettingsURLString)
        return rawStrings.compactMap(URL.init(string:))
    }
}
