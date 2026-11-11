import Foundation

/// Reads the place a pasted Google Maps, Apple Maps or `geo:` link points to, without network access.
///
/// Short share links (`maps.app.goo.gl/…`, `goo.gl/maps/…`, `maps.apple/p/…`) carry no location and
/// return `nil` here; `shortLink(_:)` recognises them so a `MapLinkExpanding` can follow the redirect.
public enum MapLinkParser {
    public enum Target: Equatable, Sendable {
        /// An exact point; `title` is the place name the link carries, if any.
        case coordinate(GeoCoordinate, title: String?)
        /// Only a name, address or other query text (which may itself be a coordinate or Plus Code).
        case text(String)
    }

    public static func parse(_ text: String) -> Target? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Android geo: URIs often carry an unencoded label such as `(Taipei 101)`.
        if trimmed.lowercased().hasPrefix("geo:") { return parseGeo(trimmed) }
        guard let (components, host) = webLink(trimmed) else { return nil }
        let link = Link(components)
        if isAppleMaps(host) { return parseApple(link) }
        if isGoogleMaps(host: host, path: link.segments) { return parseGoogle(link) }
        return nil
    }

    /// The URL of a short share link that must be expanded before it can be parsed.
    public static func shortLink(_ text: String) -> URL? {
        guard let (components, host) = webLink(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              isShortLinkHost(host, path: components.path) else { return nil }
        var secure = components
        secure.scheme = "https"
        return secure.url
    }

    /// Hosts a short-link expander may contact: the short-link services themselves.
    public static func isShortLinkHost(_ host: String, path: String) -> Bool {
        let lowered = path.lowercased()
        switch host {
        case "maps.app.goo.gl": return lowered.count > 1
        case "goo.gl": return lowered.hasPrefix("/maps/")
        case "maps.apple": return lowered.hasPrefix("/p/")
        default: return false
        }
    }

    // MARK: - Google Maps

    private static func isGoogleMaps(host: String, path: [String]) -> Bool {
        let labels = host.split(separator: ".")
        if labels.first == "maps", labels.dropFirst().first == "google" { return true }
        guard labels.contains("google") else { return false }
        return path.first?.lowercased() == "maps"
    }

    private static func parseGoogle(_ link: Link) -> Target? {
        let segments = link.segments.first?.lowercased() == "maps" ? Array(link.segments.dropFirst()) : link.segments
        let kind = segments.first?.lowercased()
        let stops = segments.dropFirst().filter { !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
        // `/dir/origin/destination/…` targets the last stop; `/place/…` and `/search/…` the first segment.
        let pathText: String? = switch kind {
        case "place", "search": stops.first
        case "dir": stops.last
        default: nil
        }
        let placeName = kind == "place" ? pathText.flatMap(nonCoordinateText) : nil

        // The `!3d…!4d…` pair in `data=` is the place itself; `@lat,lng` is only the viewport centre.
        // Direction links hold several stops in `data=`, so they rely on the destination segment instead.
        if kind != "dir", let pin = firstMatch(dataPin, in: link.rawPath) {
            return .coordinate(pin, title: placeName)
        }
        for key in ["q", "query", "destination", "daddr", "ll"] {
            if let value = link.query(key), let target = textTarget(stripLoc(value)) { return target }
        }
        if let pathText, let coordinate = coordinate(pathText) { return .coordinate(coordinate, title: nil) }
        if kind != "dir", let viewport = segments.lazy.compactMap(viewportCenter).first {
            return .coordinate(viewport, title: placeName)
        }
        if let placeName { return .text(placeName) }
        if let pathText, !pathText.isEmpty { return .text(pathText) }
        return nil
    }

    private static let dataPin = try! NSRegularExpression(pattern: #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#)

    private static func viewportCenter(_ segment: String) -> GeoCoordinate? {
        guard segment.hasPrefix("@") else { return nil }
        let parts = segment.dropFirst().split(separator: ",")
        guard parts.count >= 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        return GeoCoordinate(latitude: lat, longitude: lng)
    }

    private static func stripLoc(_ value: String) -> String {
        value.lowercased().hasPrefix("loc:") ? String(value.dropFirst(4)) : value
    }

    // MARK: - Apple Maps

    private static func isAppleMaps(_ host: String) -> Bool {
        host == "maps.apple.com" || host == "maps.apple"
    }

    private static func parseApple(_ link: Link) -> Target? {
        let name = link.query("name").flatMap(nonCoordinateText)
        // `coordinate` (unified URLs) and `ll` (legacy) mark the pin; `center` is only the viewport.
        for key in ["coordinate", "ll"] {
            if let value = link.query(key), let coordinate = coordinate(value) {
                return .coordinate(coordinate, title: name ?? link.query("q").flatMap(nonCoordinateText))
            }
        }
        for key in ["address", "q", "daddr", "destination"] {
            if let value = link.query(key), let target = textTarget(value) { return target }
        }
        if let name { return .text(name) }
        if let value = link.query("center"), let coordinate = coordinate(value) {
            return .coordinate(coordinate, title: nil)
        }
        return nil
    }

    // MARK: - geo: URI (RFC 5870, plus the Android `?q=` extension)

    private static func parseGeo(_ text: String) -> Target? {
        let body = text.dropFirst(4)
        let parts = body.split(separator: "?", maxSplits: 1)
        let pathPart = parts.first.map(String.init) ?? ""
        let queryText = parts.count > 1 ? String(parts[1]) : ""
        let query = Link.queryItems(queryText)

        if let q = query["q"] {
            // Android: `q=lat,lng(Label)` or an address.
            var value = q
            var label: String?
            if let open = value.firstIndex(of: "("), value.hasSuffix(")") {
                label = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
                    .trimmingCharacters(in: .whitespaces)
                value = String(value[..<open])
            }
            if let coordinate = coordinate(value) {
                return .coordinate(coordinate, title: label?.isEmpty == false ? label : nil)
            }
            if !q.trimmingCharacters(in: .whitespaces).isEmpty { return .text(q) }
        }
        let numbers = pathPart.split(separator: ";").first?.split(separator: ",") ?? []
        guard numbers.count >= 2, let lat = Double(numbers[0]), let lng = Double(numbers[1]),
              !(lat == 0 && lng == 0) else { return nil }
        return GeoCoordinate(latitude: lat, longitude: lng).map { .coordinate($0, title: nil) }
    }

    // MARK: - Helpers

    /// A single-token http(s) link (scheme optional) and its lower-cased host.
    private static func webLink(_ trimmed: String) -> (URLComponents, String)? {
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased() else { return nil }
        return (components, host)
    }

    private static func coordinate(_ text: String) -> GeoCoordinate? {
        if case .coordinate(let value) = CoordinateTextParser.parse(text) { return value }
        return nil
    }

    /// Coordinates become a point; anything else is passed on as query text.
    private static func textTarget(_ value: String) -> Target? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let coordinate = coordinate(trimmed) { return .coordinate(coordinate, title: nil) }
        return .text(trimmed)
    }

    private static func nonCoordinateText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, coordinate(trimmed) == nil else { return nil }
        return trimmed
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> GeoCoordinate? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let latRange = Range(match.range(at: 1), in: text),
              let lngRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]), let lng = Double(text[lngRange]) else { return nil }
        return GeoCoordinate(latitude: lat, longitude: lng)
    }
}

/// Decoded path segments and query items; `+` means a space in both, as map links use it.
private struct Link {
    let segments: [String]
    let rawPath: String
    private let items: [String: String]

    init(_ components: URLComponents) {
        rawPath = components.percentEncodedPath
        segments = rawPath.split(separator: "/").map { Link.decode(String($0)) }.filter { !$0.isEmpty }
        items = Link.queryItems(components.percentEncodedQuery ?? "")
    }

    func query(_ name: String) -> String? {
        items[name].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    static func queryItems(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let key = parts.first else { continue }
            let name = decode(String(key)).lowercased()
            if result[name] == nil { result[name] = parts.count > 1 ? decode(String(parts[1])) : "" }
        }
        return result
    }

    static func decode(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
