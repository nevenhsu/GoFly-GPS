//
//  PairingFileStore.swift
//  StikDebug
//

import Foundation
import UniformTypeIdentifiers

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(idevice)
import idevice
#endif

enum PairingFileStore {
    static let fileName = "pairingFile.plist"
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList
    ]

    private static let envelopeFileName = "pairingFile.envelope.plist"
    private static let maximumPairingFileBytes = 1 * 1024 * 1024
    private static let maximumEnvelopeBytes = maximumPairingFileBytes + 64 * 1024

    private enum StoreError: Error, LocalizedError {
        case targetBindingRequired
        case invalidTargetBinding
        case invalidPairingFile
        case pairingFileTooLarge
        case nativeValidationUnavailable
        case nativeValidationFailed
        case storageUnavailable
        case storedRecordUnavailable

        var errorDescription: String? {
            switch self {
            case .targetBindingRequired:
                return "Pairing file import requires a target device binding."
            case .invalidTargetBinding:
                return "The target device binding is invalid."
            case .invalidPairingFile:
                return "The pairing file is invalid."
            case .pairingFileTooLarge:
                return "The pairing file is too large."
            case .nativeValidationUnavailable:
                return "Pairing file validation is unavailable."
            case .nativeValidationFailed:
                return "The pairing file could not be validated."
            case .storageUnavailable:
                return "Protected pairing storage is unavailable."
            case .storedRecordUnavailable:
                return "No valid pairing file is available."
            }
        }
    }

    private struct StoredRecord {
        let pairingData: Data
        let expectedDeviceUDID: String
        let digest: Data
    }

    /// The native bridge consumes this path. It is always inside the private
    /// Application Support/Pairing directory and is materialized from the
    /// authoritative envelope by `prepareURL()`.
    static var url: URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The target binding stored with the validated pairing record. Invalid or
    /// incomplete records intentionally return nil.
    static var expectedDeviceUDID: String? {
        _ = prepareURL()
        guard let record = try? readVerifiedRecord(fileManager: .default, validateNative: true) else {
            return nil
        }
        return record.expectedDeviceUDID
    }

    /// Whether the active raw plist and its protected authoritative envelope
    /// agree and the native pairing-file reader accepts the raw path.
    static var isReady: Bool {
        verifyStoredRecord()
    }

    /// Repairs the native raw path from the authoritative envelope when it is
    /// missing or was interrupted during a previous materialization. The
    /// non-throwing signature is retained for existing callers; callers that
    /// need an actionable result should use `isReady` or `verifyStoredRecord`.
    @discardableResult
    static func prepareURL(fileManager: FileManager = .default) -> URL {
        do {
            try prepareStorage(fileManager: fileManager)
        } catch {
            // Existing callers only need the stable path. An invalid or
            // unprotected record is never considered ready and is removed from
            // the native path before this method returns.
            try? removeRawRecord(fileManager: fileManager)
        }
        return url
    }

    /// Retained for callers that already pass a source URL. Without a binding
    /// from a prior validated record this overload fails closed.
    static func replace(with sourceURL: URL, fileManager: FileManager = .default) throws {
        guard let expectedDeviceUDID else {
            throw StoreError.targetBindingRequired
        }
        try importFromPicker(sourceURL, expectedDeviceUDID: expectedDeviceUDID, fileManager: fileManager)
    }

    /// Imports and binds a pairing file to one expected device. The source is
    /// read while its security scope is active and is never copied outside the
    /// private Application Support/Pairing directory.
    static func importFromPicker(
        _ sourceURL: URL,
        expectedDeviceUDID: String,
        fileManager: FileManager = .default
    ) throws {
        try importPairingData(
            try readPickedFile(sourceURL, fileManager: fileManager),
            expectedDeviceUDID: expectedDeviceUDID,
            fileManager: fileManager
        )
    }

    /// R07.s: a sideloaded build has no Mac binding, so the target is the
    /// file's own `UDID`. Every device operation still compares the device's
    /// reported identifier with this binding (`VerifiedDeviceSession`), so a
    /// file for another iPhone fails closed before any location is sent.
    static func importSideloadedPairing(_ sourceURL: URL, fileManager: FileManager = .default) throws {
        let data = try readPickedFile(sourceURL, fileManager: fileManager)
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let udid = dictionary["UDID"] as? String else {
            throw StoreError.invalidPairingFile
        }
        try importPairingData(data, expectedDeviceUDID: udid, fileManager: fileManager)
    }

    /// Settings › 裝置與簽名 › 重新匯入配對檔 (F9.a), for both the sideload IPA
    /// and Mac-installed builds. The file must name the iPhone already bound
    /// to the stored record; with no stored record it binds like R07.s. A Mac
    /// renew later replaces this pairing through its own handoff.
    static func reimportPairing(_ sourceURL: URL, fileManager: FileManager = .default) throws {
        let data = try readPickedFile(sourceURL, fileManager: fileManager)
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let udid = dictionary["UDID"] as? String else {
            throw StoreError.invalidPairingFile
        }
        if let bound = expectedDeviceUDID, normalizeTarget(bound) != normalizeTarget(udid) {
            throw StoreError.invalidPairingFile
        }
        try importPairingData(data, expectedDeviceUDID: udid, fileManager: fileManager)
    }

    private static func readPickedFile(_ sourceURL: URL, fileManager: FileManager) throws -> Data {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StoreError.invalidPairingFile
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
              let sourceSize = (attributes[.size] as? NSNumber)?.intValue,
              sourceSize <= maximumPairingFileBytes else {
            throw StoreError.pairingFileTooLarge
        }

        do {
            return try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        } catch {
            throw StoreError.invalidPairingFile
        }
    }

    /// Existing source-compatible overload. A first import through this API is
    /// deliberately rejected because it has no explicit device binding.
    static func importFromPicker(_ sourceURL: URL, fileManager: FileManager = .default) throws {
        guard let expectedDeviceUDID else {
            throw StoreError.targetBindingRequired
        }
        try importFromPicker(sourceURL, expectedDeviceUDID: expectedDeviceUDID, fileManager: fileManager)
    }

    /// Verifies the active record, optionally requiring a particular target
    /// binding. The method is intentionally boolean so callers cannot surface
    /// native errors or record contents to logs or UI.
    static func verifyStoredRecord(
        expectedDeviceUDID: String? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        do {
            let record = try readVerifiedRecord(fileManager: fileManager, validateNative: true)
            if let expectedDeviceUDID {
                guard normalizeTarget(expectedDeviceUDID) == record.expectedDeviceUDID else {
                    return false
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Removes every app-owned pairing artifact from the private directory.
    /// No Documents, shared-container, defaults, or keychain location is
    /// consulted or modified.
    static func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw StoreError.storageUnavailable
        }
    }

    private static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    private static var envelopeURL: URL {
        directoryURL.appendingPathComponent(envelopeFileName, isDirectory: false)
    }

    private static func importPairingData(
        _ data: Data,
        expectedDeviceUDID: String,
        fileManager: FileManager
    ) throws {
        guard data.count <= maximumPairingFileBytes else {
            throw StoreError.pairingFileTooLarge
        }

        let normalizedTarget = try normalizedTargetOrThrow(expectedDeviceUDID)
        try validatePropertyListDictionary(data)
        let digest = try sha256(data)

        // Create and protect the private directory before any temporary or
        // authoritative file is written.
        try ensureDirectory(fileManager: fileManager)

        // Native validation happens against a private temporary path and that
        // path is removed before the import returns.
        try validateNativePairingData(data, fileManager: fileManager)

        let envelopeObject: [String: Any] = [
            "version": 1,
            "pairingFile": data,
            "expectedDeviceUDID": normalizedTarget,
            "sha256": digest
        ]
        let envelopeData: Data
        do {
            envelopeData = try PropertyListSerialization.data(
                fromPropertyList: envelopeObject,
                format: .binary,
                options: 0
            )
        } catch {
            throw StoreError.invalidPairingFile
        }
        guard envelopeData.count <= maximumEnvelopeBytes else {
            throw StoreError.pairingFileTooLarge
        }

        let stagedEnvelope = directoryURL.appendingPathComponent(".envelope-\(UUID().uuidString).tmp")
        let stagedRaw = directoryURL.appendingPathComponent(".pairing-\(UUID().uuidString).tmp")
        let rollbackEnvelope = directoryURL.appendingPathComponent(".rollback-envelope-\(UUID().uuidString).tmp")
        let rollbackRaw = directoryURL.appendingPathComponent(".rollback-pairing-\(UUID().uuidString).tmp")
        let hadOldEnvelope = fileManager.fileExists(atPath: envelopeURL.path)
        let hadOldRaw = fileManager.fileExists(atPath: url.path)
        do {
            try writeProtected(envelopeData, to: stagedEnvelope, fileManager: fileManager)

            // Stage the raw candidate and rollback copies before touching the
            // active paths. The old envelope remains authoritative while the
            // raw candidate is swapped, so a crash or failure before the final
            // envelope commit can only repair back to the old record.
            try writeProtected(data, to: stagedRaw, fileManager: fileManager)
            let oldEnvelope = try captureFile(at: envelopeURL, maximumBytes: maximumEnvelopeBytes, fileManager: fileManager)
            let oldRaw = try captureFile(at: url, maximumBytes: maximumPairingFileBytes, fileManager: fileManager)
            if let oldEnvelope {
                try writeProtected(oldEnvelope, to: rollbackEnvelope, fileManager: fileManager)
            }
            if let oldRaw {
                try writeProtected(oldRaw, to: rollbackRaw, fileManager: fileManager)
            }

            // This is the transaction order: materialize first, then commit
            // the authoritative envelope last. atomicReplace only moves an
            // already protected staged file, so it has no fallible security
            // work after the final envelope replacement.
            try atomicReplace(stagedRaw, at: url, fileManager: fileManager)
            try atomicReplace(stagedEnvelope, at: envelopeURL, fileManager: fileManager)

            removeTemporaryFiles(
                [rollbackEnvelope, rollbackRaw, stagedEnvelope, stagedRaw],
                fileManager: fileManager
            )
        } catch let error as StoreError {
            rollbackImport(
                envelopeBackup: rollbackEnvelope,
                rawBackup: rollbackRaw,
                hadEnvelope: hadOldEnvelope,
                hadRaw: hadOldRaw,
                fileManager: fileManager
            )
            removeTemporaryFiles(
                [rollbackEnvelope, rollbackRaw, stagedEnvelope, stagedRaw],
                fileManager: fileManager
            )
            throw error
        } catch {
            rollbackImport(
                envelopeBackup: rollbackEnvelope,
                rawBackup: rollbackRaw,
                hadEnvelope: hadOldEnvelope,
                hadRaw: hadOldRaw,
                fileManager: fileManager
            )
            removeTemporaryFiles(
                [rollbackEnvelope, rollbackRaw, stagedEnvelope, stagedRaw],
                fileManager: fileManager
            )
            throw StoreError.storageUnavailable
        }
    }

    /// Imports a pairing payload received through the private LocalGo setup
    /// handoff. The existing transactional implementation remains the single
    /// writer so a failed native validation or storage commit preserves the
    /// previous record.
    static func importSetupData(
        _ data: Data,
        expectedDeviceUDID: String,
        fileManager: FileManager = .default
    ) throws {
        try importPairingData(
            data,
            expectedDeviceUDID: expectedDeviceUDID,
            fileManager: fileManager
        )
    }

    private static func prepareStorage(fileManager: FileManager) throws {
        try ensureDirectory(fileManager: fileManager)

        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            // Files left by an older implementation have no binding and are
            // never migrated or activated.
            try removeRawRecord(fileManager: fileManager)
            return
        }

        let record = try readEnvelopeRecord(fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path),
           let rawData = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           rawData == record.pairingData {
            try protectFile(at: url, fileManager: fileManager)
        } else {
            try materializeRaw(record.pairingData, fileManager: fileManager)
        }
    }

    private static func readVerifiedRecord(
        fileManager: FileManager,
        validateNative: Bool
    ) throws -> StoredRecord {
        let record = try readEnvelopeRecord(fileManager: fileManager)

        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.storedRecordUnavailable
        }

        let rawData: Data
        do {
            rawData = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw StoreError.storedRecordUnavailable
        }
        guard rawData.count <= maximumPairingFileBytes,
              rawData == record.pairingData,
              (try? sha256(rawData)) == record.digest else {
            throw StoreError.storedRecordUnavailable
        }
        try verifyProtectedFile(at: url, fileManager: fileManager)

        if validateNative {
            try validateNativePairingFile(at: url)
        }
        return record
    }

    private static func readEnvelopeRecord(fileManager: FileManager) throws -> StoredRecord {
        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            throw StoreError.storedRecordUnavailable
        }

        let envelopeData: Data
        do {
            envelopeData = try Data(contentsOf: envelopeURL, options: [.mappedIfSafe])
        } catch {
            throw StoreError.storedRecordUnavailable
        }
        guard envelopeData.count <= maximumEnvelopeBytes else {
            throw StoreError.pairingFileTooLarge
        }
        try verifyProtectedFile(at: envelopeURL, fileManager: fileManager)

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(
                from: envelopeData,
                options: [],
                format: nil
            )
        } catch {
            throw StoreError.storedRecordUnavailable
        }
        guard let dictionary = object as? [String: Any],
              (dictionary["version"] as? NSNumber)?.intValue == 1,
              let pairingData = dictionary["pairingFile"] as? Data,
              pairingData.count <= maximumPairingFileBytes,
              let rawTarget = dictionary["expectedDeviceUDID"] as? String,
              let target = try? normalizedTargetOrThrow(rawTarget),
              let digest = dictionary["sha256"] as? Data,
              digest.count == 32,
              let calculatedDigest = try? sha256(pairingData),
              digest == calculatedDigest else {
            throw StoreError.storedRecordUnavailable
        }

        guard isValidPropertyListDictionary(pairingData) else {
            throw StoreError.invalidPairingFile
        }
        return StoredRecord(pairingData: pairingData, expectedDeviceUDID: target, digest: digest)
    }

    private static func validatePropertyListDictionary(_ data: Data) throws {
        guard isValidPropertyListDictionary(data) else {
            throw StoreError.invalidPairingFile
        }
    }

    private static func isValidPropertyListDictionary(_ data: Data) -> Bool {
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return object is [String: Any]
        } catch {
            return false
        }
    }

    private static func normalizedTargetOrThrow(_ value: String) throws -> String {
        let normalized = normalizeTarget(value)
        guard !normalized.isEmpty,
              normalized.utf8.count <= 256,
              !normalized.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            throw StoreError.invalidTargetBinding
        }
        return normalized
    }

    private static func normalizeTarget(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sha256(_ data: Data) throws -> Data {
        #if canImport(CryptoKit)
        return Data(SHA256.hash(data: data))
        #else
        throw StoreError.storageUnavailable
        #endif
    }

    private static func ensureDirectory(fileManager: FileManager) throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try protectDirectory(at: directoryURL, fileManager: fileManager)
        } catch {
            throw StoreError.storageUnavailable
        }
    }

    private static func protectDirectory(at directory: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [
                .posixPermissions: NSNumber(value: 0o700),
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: directory.path
        )
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        try verifyProtectedDirectory(at: directory, fileManager: fileManager)
    }

    private static func protectFile(at file: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [
                .posixPermissions: NSNumber(value: 0o600),
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: file.path
        )
        var protectedFile = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedFile.setResourceValues(values)
        try verifyProtectedFile(at: file, fileManager: fileManager)
    }

    private static func verifyProtectedDirectory(at directory: URL, fileManager: FileManager) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: directory.path),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o700 else {
            throw StoreError.storageUnavailable
        }
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey, .fileProtectionKey])
        guard values.isExcludedFromBackup == true,
              values.fileProtection == .completeUntilFirstUserAuthentication else {
            throw StoreError.storageUnavailable
        }
    }

    private static func verifyProtectedFile(at file: URL, fileManager: FileManager) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o600 else {
            throw StoreError.storageUnavailable
        }
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey, .fileProtectionKey])
        guard values.isExcludedFromBackup == true,
              values.fileProtection == .completeUntilFirstUserAuthentication else {
            throw StoreError.storageUnavailable
        }
    }

    private static func writeProtected(
        _ data: Data,
        to url: URL,
        fileManager: FileManager
    ) throws {
        do {
            try data.write(to: url, options: [])
            try protectFile(at: url, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: url)
            throw StoreError.storageUnavailable
        }
    }

    private static func atomicReplace(
        _ staged: URL,
        at destination: URL,
        fileManager: FileManager
    ) throws {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            throw StoreError.storageUnavailable
        }
    }

    private static func captureFile(
        at url: URL,
        maximumBytes: Int,
        fileManager: FileManager
    ) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumBytes else {
                throw StoreError.pairingFileTooLarge
            }
            return data
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storageUnavailable
        }
    }

    private static func rollbackImport(
        envelopeBackup: URL,
        rawBackup: URL,
        hadEnvelope: Bool,
        hadRaw: Bool,
        fileManager: FileManager
    ) {
        if hadEnvelope {
            if fileManager.fileExists(atPath: envelopeBackup.path) {
                do {
                    try atomicReplace(envelopeBackup, at: envelopeURL, fileManager: fileManager)
                } catch {
                    // Never leave a newly committed envelope available for
                    // prepareURL() to materialize after a failed import.
                    try? fileManager.removeItem(at: envelopeURL)
                }
            }
        } else {
            try? fileManager.removeItem(at: envelopeURL)
        }

        if hadRaw {
            if fileManager.fileExists(atPath: rawBackup.path) {
                do {
                    try atomicReplace(rawBackup, at: url, fileManager: fileManager)
                } catch {
                    try? fileManager.removeItem(at: url)
                }
            }
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func removeTemporaryFiles(_ urls: [URL], fileManager: FileManager) {
        for temporary in urls where fileManager.fileExists(atPath: temporary.path) {
            try? fileManager.removeItem(at: temporary)
        }
    }

    private static func materializeRaw(_ data: Data, fileManager: FileManager) throws {
        let staged = directoryURL.appendingPathComponent(".pairing-\(UUID().uuidString).tmp")
        do {
            try writeProtected(data, to: staged, fileManager: fileManager)
            try atomicReplace(staged, at: url, fileManager: fileManager)
        } catch let error as StoreError {
            try? fileManager.removeItem(at: staged)
            throw error
        } catch {
            try? fileManager.removeItem(at: staged)
            throw StoreError.storageUnavailable
        }
    }

    private static func validateNativePairingData(_ data: Data, fileManager: FileManager) throws {
        let temporary = directoryURL.appendingPathComponent(".validate-\(UUID().uuidString).tmp")
        do {
            try writeProtected(data, to: temporary, fileManager: fileManager)
            try validateNativePairingFile(at: temporary)
            try fileManager.removeItem(at: temporary)
        } catch let error as StoreError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw StoreError.nativeValidationFailed
        }
    }

    private static func validateNativePairingFile(at file: URL) throws {
        #if canImport(idevice)
        var pairingFile: OpaquePointer?
        let ffiError = file.path.withCString { path in
            rp_pairing_file_read(path, &pairingFile)
        }
        if let ffiError {
            idevice_error_free(ffiError)
            throw StoreError.nativeValidationFailed
        }
        guard let pairingFile else {
            throw StoreError.nativeValidationFailed
        }
        rp_pairing_file_free(pairingFile)
        #else
        throw StoreError.nativeValidationUnavailable
        #endif
    }

    private static func removeRawRecord(fileManager: FileManager) throws {
        let names = [fileName, envelopeFileName]
        for name in names {
            let candidate = directoryURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: candidate.path) {
                try fileManager.removeItem(at: candidate)
            }
        }

        guard let items = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items where item.lastPathComponent.hasPrefix(".") {
            try fileManager.removeItem(at: item)
        }
    }
}
