import Foundation
import GoFlyCore

/// Expands Google / Apple Maps short share links by reading their redirect `Location`.
/// Only the short-link hosts in `MapLinkParser.isShortLinkHost` are contacted; the expanded
/// map link itself is parsed offline and never requested. No cookies are sent or stored.
struct URLSessionMapLinkExpander: MapLinkExpanding {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private static let maxHops = 3

    func expand(_ shortLink: URL) async throws -> URL? {
        var current = shortLink
        for _ in 0..<Self.maxHops {
            guard current.scheme?.lowercased() == "https", let host = current.host()?.lowercased(),
                  MapLinkParser.isShortLinkHost(host, path: current.path()) else { return nil }
            let request = URLRequest(url: current, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (_, response) = try await Self.session.data(for: request, delegate: RedirectStopper())
            guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: current)?.absoluteURL else { return nil }
            if MapLinkParser.parse(next.absoluteString) != nil { return next }
            current = next
        }
        return nil
    }
}

/// Keeps URLSession from following redirects, so the expander sees each `Location` itself.
private final class RedirectStopper: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
