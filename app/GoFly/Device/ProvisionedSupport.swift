import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)

enum SupportMountMethod: String { case personalized, cryptex }

struct ProvisionedSupport {
    let directory: URL

    /// Picks the support set to mount. A Mac install has a formal set from
    /// its activation; settings › 裝置支援 can also download one into
    /// `Documents/DDI`. The downloaded set is used when it is complete for this
    /// iOS version and either no formal set fits (e.g. after an iOS update
    /// changed the mount method) or it was written after the formal set.
    init(method: SupportMountMethod) throws {
        let formalDirectory: URL?
        let formalFailed: Bool
        do {
            let setupMethod: SetupSupportMethod = method == .cryptex ? .cryptex : .personalized
            formalDirectory = try SetupActivationStore(directory: try GoFlySetupPaths.directory())
                .activeSupportDirectory(method: setupMethod)
            formalFailed = false
        } catch {
            formalDirectory = nil
            formalFailed = true
        }
        let downloaded = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DDI", isDirectory: true)
        let downloadedComplete = downloaded.map { Self.isComplete($0, method: method) } ?? false

        if let formalDirectory {
            if downloadedComplete, let downloaded,
               Self.manifestDate(downloaded) > Self.manifestDate(formalDirectory) {
                directory = downloaded
            } else {
                directory = formalDirectory
            }
        } else if let downloaded, !formalFailed || downloadedComplete {
            directory = downloaded
        } else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
        guard Self.isComplete(directory, method: method) else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
    }

    private static func files(for method: SupportMountMethod) -> [String] {
        ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
            + (method == .cryptex ? ["Image.dmg.cryptex_info", "Image.dmg.root_hash"] : [])
    }

    private static func isComplete(_ directory: URL, method: SupportMountMethod) -> Bool {
        let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues?.isDirectory == true, directoryValues?.isSymbolicLink != true else { return false }
        let filesOK = files(for: method).allSatisfy { name in
            let values = try? directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? 0) > 0
        }
        return filesOK && (try? String(contentsOf: directory.appendingPathComponent("MountMethod"), encoding: .utf8)) == method.rawValue
    }

    private static func manifestDate(_ directory: URL) -> Date {
        (try? directory.appendingPathComponent("BuildManifest.plist")
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// True when a set this method can mount exists (formal or downloaded).
    static func isAvailable(method: SupportMountMethod) -> Bool {
        (try? ProvisionedSupport(method: method)) != nil
    }

    func data(_ name: String) throws -> Data {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name), options: [.mappedIfSafe]), !data.isEmpty else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
        return data
    }
}

#endif
