import Foundation

/// Minimal Open Location Code ("Plus Code") support: validation, decoding of full codes, and
/// recovery of short codes from a reference point. Algorithm per the public OLC specification
/// (github.com/google/open-location-code); padded codes such as `8FVC0000+` are not accepted.
public enum OpenLocationCode {
    static let alphabet = Array("23456789CFGHJMPQRVWX")
    static let separator: Character = "+"
    static let separatorPosition = 8
    static let pairCodeLength = 10
    static let maxDigits = 15

    public enum Kind: Equatable, Sendable { case full, short }

    /// The upper-cased code if `text` is a valid unpadded code, along with its kind.
    public static func classify(_ text: String) -> (code: String, kind: Kind)? {
        let code = text.uppercased()
        let characters = Array(code)
        guard let separatorIndex = characters.firstIndex(of: separator),
              characters.lastIndex(of: separator) == separatorIndex,
              separatorIndex <= separatorPosition, separatorIndex >= 2, separatorIndex % 2 == 0 else { return nil }
        let suffixCount = characters.count - separatorIndex - 1
        guard suffixCount != 1, characters.count - 1 <= maxDigits else { return nil }
        let digits = characters.filter { $0 != separator }
        guard digits.allSatisfy(alphabet.contains) else { return nil }
        // A short code always carries digits after "+"; this also keeps text like "22+" a name.
        if separatorIndex < separatorPosition { return suffixCount >= 2 ? (code, .short) : nil }
        // The first two digits encode latitude (< 180°) and longitude (< 360°) in 20° steps.
        guard let lat = value(of: digits[0]), lat < 9, let lng = value(of: digits[1]), lng < 18 else { return nil }
        return (code, .full)
    }

    /// The centre of a full code's area.
    public static func decode(_ fullCode: String) -> GeoCoordinate? {
        guard let (code, kind) = classify(fullCode), kind == .full else { return nil }
        let digits = code.filter { $0 != separator }.compactMap(value(of:))
        var latitude = -90.0, longitude = -180.0
        var latResolution = 400.0, lngResolution = 400.0
        for index in stride(from: 0, to: min(digits.count, pairCodeLength), by: 2) {
            latResolution /= 20; lngResolution /= 20
            latitude += Double(digits[index]) * latResolution
            longitude += Double(digits[index + 1]) * lngResolution
        }
        for digit in digits.dropFirst(pairCodeLength) {
            latResolution /= 5; lngResolution /= 4
            latitude += Double(digit / 4) * latResolution
            longitude += Double(digit % 4) * lngResolution
        }
        let centerLatitude = min(90, latitude + latResolution / 2)
        let centerLongitude = normalizeLongitude(longitude + lngResolution / 2)
        return GeoCoordinate(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// The full-code centre nearest to `reference` for a short code such as `4QM3+M6`.
    public static func recoverNearest(_ shortCode: String, reference: GeoCoordinate) -> GeoCoordinate? {
        guard let (code, kind) = classify(shortCode) else { return nil }
        if kind == .full { return decode(code) }
        let missing = separatorPosition - code.prefix { $0 != separator }.count
        let prefix = encodePairs(reference, digits: missing)
        guard let center = decode(prefix + code) else { return nil }
        // Area covered by the missing digits, in degrees.
        let resolution = pow(20.0, 2 - Double(missing / 2))
        let half = resolution / 2
        var latitude = center.latitude, longitude = center.longitude
        if reference.latitude + half < latitude, latitude - resolution >= -90 {
            latitude -= resolution
        } else if reference.latitude - half > latitude, latitude + resolution <= 90 {
            latitude += resolution
        }
        if reference.longitude + half < longitude {
            longitude -= resolution
        } else if reference.longitude - half > longitude {
            longitude += resolution
        }
        return GeoCoordinate(latitude: latitude, longitude: normalizeLongitude(longitude))
    }

    /// The first `digits` pair digits for a coordinate (enough to complete a short code's prefix).
    static func encodePairs(_ coordinate: GeoCoordinate, digits: Int) -> String {
        var latitude = min(coordinate.latitude, 90 - 1e-10) + 90
        var longitude = normalizeLongitude(coordinate.longitude) + 180
        if longitude >= 360 { longitude -= 360 }
        var resolution = 20.0
        var result = ""
        while result.count < digits {
            let latDigit = min(19, Int(latitude / resolution)), lngDigit = min(19, Int(longitude / resolution))
            result.append(alphabet[latDigit]); result.append(alphabet[lngDigit])
            latitude -= Double(latDigit) * resolution
            longitude -= Double(lngDigit) * resolution
            resolution /= 20
        }
        return String(result.prefix(digits))
    }

    private static func value(of character: Character) -> Int? { alphabet.firstIndex(of: character) }

    private static func normalizeLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value < -180 { value += 360 }
        while value >= 180 { value -= 360 }
        return value
    }
}

/// A pasted Plus Code with an optional locality, e.g. `4QM3+M6 North Beach, Western Australia`.
public struct PlusCodeQuery: Equatable, Sendable {
    public let code: String
    public let kind: OpenLocationCode.Kind
    public let locality: String?

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.prefix { !$0.isWhitespace && $0 != "," && $0 != "，" }
        guard let (code, kind) = OpenLocationCode.classify(String(head)) else { return nil }
        let rest = trimmed.dropFirst(head.count)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，")))
        self.code = code
        self.kind = kind
        self.locality = rest.isEmpty ? nil : rest
    }
}
