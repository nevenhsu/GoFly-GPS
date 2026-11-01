import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)
import Darwin
import idevice

/// Timings for one point tick. Never retains FFI messages, only call names,
/// durations and numeric codes.
final class FFITrace {
    struct Call {
        let name: String
        let milliseconds: Double
    }

    private(set) var calls: [Call] = []
    private(set) var failureOperation: String?
    private(set) var failureCode: Int32?
    private(set) var failureSubcode: Int32?

    func record(_ name: String, milliseconds: Double) {
        guard calls.count < 32 else { return }
        calls.append(Call(name: name, milliseconds: milliseconds))
    }

    func noteFailure(operation: String, code: Int32, subcode: Int32) {
        failureOperation = operation
        failureCode = code
        failureSubcode = subcode
    }

    var totalMilliseconds: Double { calls.reduce(0) { $0 + $1.milliseconds } }

    var callsText: String {
        calls.map { "\($0.name)=\(Self.milliseconds($0.milliseconds))" }.joined(separator: ",")
    }

    static func milliseconds(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.1f", arguments: [value])
    }
}

// Tunnel, personalized/cryptex mounting and location-channel ownership logic
// adapted from StikDebug (AGPL-3.0), JITEnableContext.swift and
// IdeviceFFIBridge.swift. See the production target's license/provenance files.
// This class does not import their global contexts, caches or command queues.
final class NativeDeviceSession: DeviceSession {
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var location: OpaquePointer?
    private var trace: FFITrace?
    private var operationDeadlineNanoseconds: UInt64?

    init(pairingURL: URL, operationDeadlineNanoseconds: UInt64? = nil) throws {
        // Store the deadline before touching pairing or tunnel handles. A
        // constructor that begins too late must fail without opening a new
        // native connection.
        self.operationDeadlineNanoseconds = operationDeadlineNanoseconds
        var pairing: OpaquePointer?
        defer { if let pairing { rp_pairing_file_free(pairing) } }
        do {
            let read = try ffi("pairing.read") {
                pairingURL.path.withCString { rp_pairing_file_read($0, &pairing) }
            }
            try check(read, .pairingRequired, operation: "rp_pairing_file_read")
            guard let pairing else { throw DeviceServiceFailure.pairingRequired }
            var address = try localTunnelAddress()
            let created = try ffi("tunnel.create") {
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        tunnel_create_rppairing_verify_only(
                            $0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                            "GoFlyService", pairing, &adapter, &handshake
                        )
                    }
                }
            }
            try check(created, .tunnelUnavailable, operation: "tunnel_create_rppairing_verify_only")
            guard adapter != nil, handshake != nil else { throw DeviceServiceFailure.tunnelUnavailable }
        } catch {
            close()
            throw error
        }
    }

    func beginTrace() { trace = FFITrace() }

    func endTrace() -> FFITrace? {
        defer { trace = nil }
        return trace
    }

    func setOperationDeadline(_ deadline: UInt64?) {
        operationDeadlineNanoseconds = deadline
    }

    func close() {
        if let location { location_simulation_free(location); self.location = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
        Diagnostics.shared.record("device.session", category: .device, level: .notice,
                                  ["event": .text("closed")])
    }

    func deviceIdentifier() throws -> String { try stringValue("UniqueDeviceID") }

    func isSupportPrepared() throws -> Bool {
        if try mountMethod() == .cryptex {
            var installed: UnsafeMutablePointer<InstalledCryptexC>?
            defer { cryptexd_free_installed_cryptex(installed) }
            try check(try ffi("cryptex.installed") { cryptexd_installed_ddi(adapter, handshake, &installed) },
                      .devicePreparationRequired, operation: "cryptexd_installed_ddi")
            return installed != nil
        }
        return try withImageMounter { client in
            var signature: UnsafeMutablePointer<UInt8>?
            var count = 0
            defer { if let signature { idevice_data_free(signature, UInt(count)) } }
            let lookup = try ffi("image.lookup") {
                image_mounter_lookup_image(client, "Personalized", &signature, &count)
            }
            if let error = lookup {
                // Native library's NotFound (20) is the sole absent-image case.
                // Transport/protocol failures cannot trigger a blind mount.
                let code = error.pointee.code
                let subcode = error.pointee.sub_code
                let absent = NativeErrorMapping.isNotMounted(code: code, subcode: subcode)
                let failure = NativeErrorMapping.failure(code: code, subcode: subcode,
                                                         fallback: .devicePreparationRequired)
                idevice_error_free(error)
                recordFailure(code: code, subcode: subcode, operation: "image_mounter_lookup_image",
                              mapped: failure)
                if absent { return false }
                throw failure
            }
            return signature != nil && count > 0
        }
    }

    func mountProvisionedSupport() throws {
        let method = try mountMethod()
        let support = try ProvisionedSupport(method: method)
        if method == .cryptex {
            var assets: OpaquePointer?
            defer { if let assets { cryptex1_assets_free(assets) } }
            let loaded = try ffi("cryptex.loadAssets") { support.directory.path.withCString { cryptex1_assets_load($0, &assets) } }
            try check(loaded, .devicePreparationRequired, operation: "cryptex1_assets_load")
            guard let assets else { throw DeviceServiceFailure.devicePreparationRequired }
            // Explicit user preparation may invoke native Apple signing. The
            // app itself only reads support already provisioned by the Mac.
            try check(try ffi("cryptex.installDDI") { cryptexd_install_ddi(adapter, handshake, assets, nil) },
                      .devicePreparationRequired, operation: "cryptexd_install_ddi")
        } else {
            let image = try support.data("Image.dmg")
            let trustcache = try support.data("Image.dmg.trustcache")
            let manifest = try support.data("BuildManifest.plist")
            let chipID = try unsignedValue("UniqueChipID")
            try withImageMounter { client in
                let mounted = try ffi("image.mount") {
                    image.withUnsafeBytes { imageBytes in
                        trustcache.withUnsafeBytes { cacheBytes in
                            manifest.withUnsafeBytes { manifestBytes in
                                image_mounter_mount_personalized_rsd(
                                    client, adapter, handshake,
                                    imageBytes.bindMemory(to: UInt8.self).baseAddress, image.count,
                                    cacheBytes.bindMemory(to: UInt8.self).baseAddress, trustcache.count,
                                    manifestBytes.bindMemory(to: UInt8.self).baseAddress, manifest.count,
                                    nil, chipID
                                )
                            }
                        }
                    }
                }
                try check(mounted, .devicePreparationRequired, operation: "image_mounter_mount_personalized_rsd")
            }
        }
    }

    func validateLocationService() throws {
        if location != nil { return }
        try check(try ffi("rsd.connect") { remote_server_connect_rsd(adapter, handshake, &remoteServer) },
                  .serviceUnavailable, operation: "remote_server_connect_rsd")
        guard remoteServer != nil else { throw DeviceServiceFailure.serviceUnavailable }
        try check(try ffi("location.new") { location_simulation_new(remoteServer, &location) },
                  .serviceUnavailable, operation: "location_simulation_new")
        guard location != nil else { throw DeviceServiceFailure.serviceUnavailable }
        // Opening a channel validates readiness without setting a coordinate.
    }

    func setLocation(_ coordinate: GeoCoordinate) throws {
        // Preparation opens the channel before the final dispatch gate.
        guard let location else { throw DeviceServiceFailure.serviceUnavailable }
        try check(try ffi("location.set") { location_simulation_set(location, coordinate.latitude, coordinate.longitude) },
                  .serviceUnavailable, operation: "location_simulation_set")
    }

    func clearLocation() throws {
        try validateLocationService()
        try check(try ffi("location.clear") { location_simulation_clear(location) },
                  .serviceUnavailable, operation: "location_simulation_clear")
    }

    private func mountMethod() throws -> SupportMountMethod {
        let components = try stringValue("ProductVersion").split(separator: ".")
        guard let major = components.first.flatMap({ Int($0) }),
              major >= 26 else { throw DeviceServiceFailure.devicePreparationRequired }
        let minor = components.count > 1 ? Int(components[1]) : 0
        guard let minor else { throw DeviceServiceFailure.devicePreparationRequired }
        return major > 26 || minor >= 4 ? .cryptex : .personalized
    }

    private func withLockdown<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var client: OpaquePointer?
        defer { if let client { lockdownd_client_free(client) } }
        try check(try ffi("lockdown.connect") { lockdownd_connect_rsd(adapter, handshake, &client) },
                  .serviceUnavailable, operation: "lockdownd_connect_rsd")
        guard let client else { throw DeviceServiceFailure.serviceUnavailable }
        return try operation(client)
    }

    private func withImageMounter<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var client: OpaquePointer?
        defer { if let client { image_mounter_free(client) } }
        try check(try ffi("image.connect") { image_mounter_connect_rsd(adapter, handshake, &client) },
                  .devicePreparationRequired, operation: "image_mounter_connect_rsd")
        guard let client else { throw DeviceServiceFailure.devicePreparationRequired }
        return try operation(client)
    }

    private func stringValue(_ key: String) throws -> String {
        try withLockdown { client in
            var value: plist_t?
            defer { plist_free(value) }
            try check(try ffi("lockdown.value") { key.withCString { lockdownd_get_value(client, $0, nil, &value) } },
                      .serviceUnavailable, operation: "lockdownd_get_value")
            guard let value, plist_get_node_type(value) == PLIST_STRING else {
                throw DeviceServiceFailure.serviceUnavailable
            }
            var count: UInt64 = 0
            guard let bytes = plist_get_string_ptr(value, &count), count > 0, count <= 256,
                  let result = String(bytes: UnsafeBufferPointer(start: UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: Int(count)), encoding: .utf8) else {
                throw DeviceServiceFailure.serviceUnavailable
            }
            return result
        }
    }

    private func unsignedValue(_ key: String) throws -> UInt64 {
        try withLockdown { client in
            var value: plist_t?
            defer { plist_free(value) }
            try check(try ffi("lockdown.value") { key.withCString { lockdownd_get_value(client, $0, nil, &value) } },
                      .devicePreparationRequired, operation: "lockdownd_get_value")
            guard let value, plist_get_node_type(value) == PLIST_INT else {
                throw DeviceServiceFailure.devicePreparationRequired
            }
            var result: UInt64 = 0
            plist_get_uint_val(value, &result)
            guard result != 0 else { throw DeviceServiceFailure.devicePreparationRequired }
            return result
        }
    }

    private func ffi<T>(_ name: String, _ call: () -> T) throws -> T {
        try requireOperationBudget()
        idevice_set_global_timeout(timeoutSeconds())
        let start = DispatchTime.now().uptimeNanoseconds
        let value = call()
        trace?.record(name, milliseconds: Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
        return value
    }

    private func requireOperationBudget() throws {
        guard let deadline = operationDeadlineNanoseconds else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline > now, deadline - now >= 1_000_000_000 else {
            throw DeviceServiceFailure.operationTimedOut
        }
    }

    private func timeoutSeconds() -> UInt64 {
        guard let deadline = operationDeadlineNanoseconds else { return 10 }
        let now = DispatchTime.now().uptimeNanoseconds
        let remaining = deadline > now ? deadline - now : 0
        return min(UInt64(10), max(UInt64(1), remaining / 1_000_000_000))
    }

    /// Only numbers are retained; the FFI message is freed immediately.
    private func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, _ fallback: DeviceServiceFailure,
                       operation: String) throws {
        guard let error else { return }
        let code = error.pointee.code
        let subcode = error.pointee.sub_code
        let failure = NativeErrorMapping.failure(code: code, subcode: subcode, fallback: fallback)
        idevice_error_free(error)
        recordFailure(code: code, subcode: subcode, operation: operation, mapped: failure)
        throw failure
    }

    private func recordFailure(code: Int32, subcode: Int32, operation: String, mapped: DeviceServiceFailure) {
        trace?.noteFailure(operation: operation, code: code, subcode: subcode)
        Diagnostics.shared.record("ffi.error", category: .device, level: .notice, [
            "op": .text(operation),
            "code": .code(code),
            "subcode": .code(subcode),
            "mapped": .text(mapped.rawValue)
        ])
    }
}

#endif
