import Foundation

public enum LocalTunnelEndpoint {
    public static let host = "10.7.0.1"
    /// remotepairingd's port is assigned by iOS and found by `RemotePairingPort`; nil until one was found.
    public static var port: UInt16? { RemotePairingPort.current }
    public static let timeoutSeconds: TimeInterval = 2
}
