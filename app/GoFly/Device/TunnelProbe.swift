import Foundation
import GoFlyCore
import GoFlyTransport

#if !targetEnvironment(simulator)
import Darwin

/// A fresh TCP probe for the fixed LocalDevVPN endpoint.
enum TunnelProbe {
    static func run() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DeviceServiceFailure.tunnelUnavailable }
        defer { Darwin.close(descriptor) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else {
            throw DeviceServiceFailure.tunnelUnavailable
        }
        var address = try localTunnelAddress()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        if result == 0 { return }
        guard errno == EINPROGRESS else { throw DeviceServiceFailure.tunnelUnavailable }
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pollDescriptor, 1, Int32(LocalTunnelEndpoint.timeoutSeconds * 1_000))
        guard ready > 0 else {
            throw ready == 0 ? DeviceServiceFailure.operationTimedOut : .tunnelUnavailable
        }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0,
              socketError == 0 else { throw DeviceServiceFailure.tunnelUnavailable }
    }
}

func localTunnelAddress() throws -> sockaddr_in {
    // The port is whatever remotepairingd advertised; without one there is nothing to connect to.
    guard let port = LocalTunnelEndpoint.port else { throw DeviceServiceFailure.tunnelUnavailable }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    // The transport is a LocalDevVPN host with a discovered port, never user/defaults input.
    _ = LocalTunnelEndpoint.host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    return address
}

#endif
