import GoFlyCore

/// Numeric native failures remain private to the device boundary. Never retain
/// an FFI message: it can contain pairing material, device IDs or local paths.
enum NativeErrorMapping {
    static func isNotMounted(code: Int32, subcode: Int32) -> Bool {
        code == 20
    }

    static func failure(code: Int32, subcode: Int32, fallback: DeviceServiceFailure) -> DeviceServiceFailure {
        if code == 103 && subcode == 5 { return .pairingRejected }
        if code == 109 { return .operationTimedOut }
        if code == 24 && subcode == 0 { return .developerModeRequired }
        return fallback
    }
}
