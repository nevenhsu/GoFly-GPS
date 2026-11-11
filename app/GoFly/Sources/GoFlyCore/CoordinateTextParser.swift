import Foundation

/// Reads the coordinate notations Google Maps and similar tools copy to the clipboard.
///
/// Accepted forms (either order when hemispheres are given, otherwise latitude first):
/// `25.0340, 121.5645` · `25.0340 121.5645` · `(-31.87, 115.75)` · `[-31.87, 115.75]`
/// `31.86650° S, 115.75419° E` · `S 31.8665, E 115.7542`
/// `31°51'49.7"S 115°45'07.0"E` · `31°51.828'S 115°45.117'E` · `南緯 31.8665, 東經 115.7542`
public enum CoordinateTextParser {
    public enum Outcome: Equatable, Sendable {
        case coordinate(GeoCoordinate)
        /// The text is clearly meant as a coordinate but cannot be used.
        case invalid(CoordinateInputFailure)
        /// Ordinary text: hand it to place search.
        case notCoordinate
    }

    public static func parse(_ text: String) -> Outcome {
        let normalized = normalize(text)
        guard normalized.contains(where: \.isASCIIDigit),
              normalized.allSatisfy(isCoordinateCharacter) else { return .notCoordinate }

        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = pairPatterns.lazy.compactMap({ $0.firstMatch(in: normalized, range: range) }).first else {
            return looksLikeCoordinate(normalized) ? .invalid(.format) : .notCoordinate
        }
        let hasMarkers = normalized.contains { ",;°'\"NSEWnsew".contains($0) }
        guard let first = component(match, offset: 1, in: normalized),
              let second = component(match, offset: 7, in: normalized) else { return .invalid(.format) }
        // Two bare whitespace-separated numbers ("7 11") are more likely a name than a coordinate.
        if !hasMarkers, !(first.hasFraction && second.hasFraction) { return .notCoordinate }
        guard let pair = orient(first, second) else { return .invalid(.format) }
        guard (-90...90).contains(pair.latitude) else { return .invalid(.latitudeRange) }
        guard (-180...180).contains(pair.longitude) else { return .invalid(.longitudeRange) }
        guard let coordinate = GeoCoordinate(latitude: pair.latitude, longitude: pair.longitude) else {
            return .invalid(.format)
        }
        return .coordinate(coordinate)
    }

    // MARK: - Normalization

    private static let replacements: [(String, String)] = [
        ("北緯", "N"), ("北纬", "N"), ("南緯", "S"), ("南纬", "S"),
        ("東經", "E"), ("东经", "E"), ("西經", "W"), ("西经", "W"),
        ("，", ","), ("；", ";"), ("（", "("), ("）", ")"), ("［", "["), ("］", "]"),
        ("－", "-"), ("−", "-"), ("＋", "+"), ("．", "."),
        ("º", "°"), ("˚", "°"),
        ("′′", "\""), ("''", "\""), ("″", "\""), ("“", "\""), ("”", "\""), ("＂", "\""),
        ("′", "'"), ("’", "'"), ("‘", "'"), ("´", "'"), ("＇", "'"),
    ]

    static func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (from, to) in replacements { value = value.replacingOccurrences(of: from, with: to) }
        value = String(value.map { $0.isWhitespace ? " " : $0 })
        // Full-width digits from CJK keyboards.
        value = value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
        if let open = value.first, let close = value.last, value.count >= 2,
           (open == "(" && close == ")") || (open == "[" && close == "]") {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    private static func isCoordinateCharacter(_ character: Character) -> Bool {
        character.isASCIIDigit || " .,;+-°'\"NSEWnsew".contains(character)
    }

    /// Only coordinate characters, and shaped like an attempt at a pair: report a format error.
    private static func looksLikeCoordinate(_ text: String) -> Bool {
        if text.contains(where: { ",;°'\"".contains($0) }) { return true }
        let numbers = text.split(whereSeparator: { !$0.isASCIIDigit && $0 != "." }).filter { !$0.isEmpty }
        return numbers.count >= 2 && text.contains(where: { "NSEWnsew".contains($0) })
    }

    // MARK: - Matching

    /// Six groups per component: leading hemisphere, sign, degrees, minutes, seconds, trailing hemisphere.
    /// A component carries its hemisphere either before or after the number, never both, so the
    /// leading-only and trailing-only layouts are matched separately; `()` keeps group numbers aligned.
    private static let componentBody =
        #"\s*([+-])?\s*(\d+(?:\.\d+)?)\s*°?\s*(?:(\d+(?:\.\d+)?)\s*'\s*)?(?:(\d+(?:\.\d+)?)\s*"\s*)?"#
    private static let pairPatterns: [NSRegularExpression] = {
        let leading = "([NSEW])?" + componentBody + "()"
        let trailing = "()" + componentBody + "([NSEW])?"
        // The patterns are compile-time constants.
        return [leading, trailing].map { component in
            try! NSRegularExpression(pattern: "^\(component)(?:\\s*[,;]\\s*|\\s+)\(component)$",
                                     options: [.caseInsensitive])
        }
    }()

    private enum Axis { case latitude, longitude }

    private struct Component {
        let value: Double
        let axis: Axis?
        let hasFraction: Bool
    }

    private static func component(_ match: NSTextCheckingResult, offset: Int, in text: String) -> Component? {
        func group(_ index: Int) -> String? {
            let range = match.range(at: offset + index)
            guard range.location != NSNotFound, range.length > 0,
                  let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
        // Each pattern captures at most one of the leading and trailing hemisphere groups.
        let hemisphere = (group(0) ?? group(5))?.uppercased()
        let negativeSign = group(1) == "-"

        guard let degreesText = group(2), let degrees = Double(degreesText) else { return nil }
        let minutesText = group(3)
        let secondsText = group(4)
        let minutes = minutesText.flatMap(Double.init) ?? 0
        let seconds = secondsText.flatMap(Double.init) ?? 0
        if minutesText != nil {
            guard !degreesText.contains("."), minutes < 60 else { return nil }
        }
        if let secondsText {
            guard minutesText?.contains(".") == false, seconds < 60, !secondsText.isEmpty else { return nil }
        }
        var value = degrees + minutes / 60 + seconds / 3600

        var axis: Axis?
        switch hemisphere {
        case "N"?, "E"?:
            if negativeSign { return nil }
            axis = hemisphere == "N" ? .latitude : .longitude
        case "S"?, "W"?:
            value = -value
            axis = hemisphere == "S" ? .latitude : .longitude
        default:
            if negativeSign { value = -value }
        }
        let hasFraction = degreesText.contains(".") || minutesText != nil || secondsText != nil
        return Component(value: value, axis: axis, hasFraction: hasFraction)
    }

    private static func orient(_ first: Component, _ second: Component) -> (latitude: Double, longitude: Double)? {
        switch (first.axis, second.axis) {
        case (.latitude?, .latitude?), (.longitude?, .longitude?): return nil
        case (.longitude?, _), (_, .latitude?): return (second.value, first.value)
        default: return (first.value, second.value)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
