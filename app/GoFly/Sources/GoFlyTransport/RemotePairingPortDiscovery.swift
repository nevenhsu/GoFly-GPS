import Foundation
import GoFlyCore
#if canImport(Darwin)
import Darwin
#endif

/// The port of this iPhone's own remotepairingd. iOS picks it dynamically and
/// advertises it over Bonjour; nothing here assumes a fixed port.
public enum RemotePairingPort {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var discovered: UInt16?

    public static var current: UInt16? { lock.withLock { discovered } }

    static func remember(_ port: UInt16) { lock.withLock { discovered = port } }

    /// Browses `_remotepairing._tcp` and returns the port of the service that
    /// is hosted on this device (its resolved address is one of our own).
    /// Returns nil when nothing local is found within `timeout`.
    public static func discover(timeout: TimeInterval) async -> UInt16? {
        let port: UInt16? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let finder = Finder(timeout: timeout) { continuation.resume(returning: $0) }
                finder.start()
            }
        }
        if let port { remember(port) }
        return port
    }

    private final class Finder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
        private let browser = NetServiceBrowser()
        private var services: [NetService] = []
        private var done: ((UInt16?) -> Void)?
        private let timeout: TimeInterval

        init(timeout: TimeInterval, done: @escaping (UInt16?) -> Void) {
            self.timeout = timeout
            self.done = done
        }

        func start() {
            browser.delegate = self
            browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
        }

        private func finish(_ port: UInt16?) {
            guard let done else { return }
            self.done = nil
            browser.stop()
            services.forEach { $0.stop() }
            services.removeAll()
            done(port)
        }

        func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: timeout)
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            let local = Self.localAddressBytes()
            let hosted = (sender.addresses ?? []).contains { Self.addressBytes($0).map(local.contains) == true }
            if hosted, sender.port > 0, sender.port <= Int(UInt16.max) { finish(UInt16(sender.port)) }
        }

        private static func addressBytes(_ data: Data) -> Data? {
            data.withUnsafeBytes { raw -> Data? in
                guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr>.size else { return nil }
                switch Int32(base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family) {
                case AF_INET where raw.count >= MemoryLayout<sockaddr_in>.size:
                    let a = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                    return withUnsafeBytes(of: a) { Data($0) }
                case AF_INET6 where raw.count >= MemoryLayout<sockaddr_in6>.size:
                    let a = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    return withUnsafeBytes(of: a) { Data($0) }
                default: return nil
                }
            }
        }

        private static func localAddressBytes() -> Set<Data> {
            var result = Set<Data>()
            var list: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&list) == 0 else { return result }
            defer { freeifaddrs(list) }
            var cursor = list
            while let entry = cursor {
                if let addr = entry.pointee.ifa_addr {
                    let family = Int32(addr.pointee.sa_family)
                    if family == AF_INET || family == AF_INET6 {
                        let size = family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size
                        if let bytes = addressBytes(Data(bytes: addr, count: size)) { result.insert(bytes) }
                    }
                }
                cursor = entry.pointee.ifa_next
            }
            return result
        }
    }
}
