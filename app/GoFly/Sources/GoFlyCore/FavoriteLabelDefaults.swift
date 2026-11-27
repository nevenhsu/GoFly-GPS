import Foundation

public enum FavoriteLabelDefaults {
    /// Simplified coordinate text (4 decimals, ~11 m precision) used when no place, street, or area name is available.
    public static func simplifiedCoordinate(_ coordinate: GeoCoordinate) -> String {
        String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"),
               coordinate.latitude, coordinate.longitude)
    }

    /// International-aware default name for a favorite place:
    /// 1. Place / POI / landmark / store / street name (`place.title`, when distinct from full address and raw coordinates)
    /// 2. Concise street or area name extracted from `place.address`
    /// 3. Simplified coordinates (`%.4f, %.4f`)
    public static func defaultName(for place: MapPlace) -> String {
        defaultPlaceName(title: place.title, address: place.address, coordinate: place.coordinate)
    }

    public static func defaultPlaceName(title: String?, address: String?, coordinate: GeoCoordinate) -> String {
        let cleanedTitle = normalizedLine(title)
        let cleanedAddress = normalizedLine(address)

        if let cleanedTitle, !isRawCoordinate(cleanedTitle, coordinate: coordinate) {
            if cleanedAddress == nil || cleanedTitle != cleanedAddress {
                return clamped(cleanedTitle, limit: FavoritePlacesLimits.labelCharacters)
            }
        }

        if let sourceAddress = cleanedAddress ?? cleanedTitle,
           !isRawCoordinate(sourceAddress, coordinate: coordinate),
           let concise = conciseAddressName(from: sourceAddress) {
            return clamped(concise, limit: FavoritePlacesLimits.labelCharacters)
        }

        return simplifiedCoordinate(coordinate)
    }

    /// Default name for a saved favorite route:
    /// 1. GPX filename without `.gpx` extension
    /// 2. `Start → End` using each endpoint's default place name
    public static func defaultName(for record: FavoriteRouteRecord) -> String {
        switch record.sourceKind {
        case .gpx:
            if let stripped = strippedGPXName(record.displayFilename) {
                return clamped(stripped, limit: FavoriteRoutesLimits.labelCharacters)
            }
            return joinEndpoints(
                simplifiedCoordinate(record.start),
                simplifiedCoordinate(record.end)
            )
        case .manual:
            let start = defaultPlaceName(title: record.startTitle, address: nil, coordinate: record.start)
            let end = defaultPlaceName(title: record.endTitle, address: nil, coordinate: record.end)
            return joinEndpoints(start, end)
        }
    }

    /// Default name for a route draft before saving.
    public static func defaultName(
        for draft: RouteDraft,
        currentRouteOrigin: GeoCoordinate? = nil,
        currentLocationFallback: String? = nil
    ) -> String {
        if let source = draft.gpxSource,
           let stripped = strippedGPXName(source.displayFilename) {
            return clamped(stripped, limit: FavoriteRoutesLimits.labelCharacters)
        }

        var endpointNames: [String] = []
        for node in draft.nodes {
            switch node.value {
            case .place(let place):
                endpointNames.append(defaultName(for: place))
            case .current:
                if let origin = currentRouteOrigin {
                    endpointNames.append(simplifiedCoordinate(origin))
                } else if let fallback = normalizedLine(currentLocationFallback) {
                    endpointNames.append(fallback)
                }
            case .empty:
                continue
            }
        }

        guard let first = endpointNames.first else {
            return normalizedLine(currentLocationFallback) ?? ""
        }
        if endpointNames.count >= 2, let last = endpointNames.last {
            return joinEndpoints(first, last)
        }
        return clamped(first, limit: FavoriteRoutesLimits.labelCharacters)
    }

    public static func resolved(_ draft: String, fallback: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: - Helpers

    private static let commaSeparators = CharacterSet(charactersIn: ",，、")

    private static func normalizedLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func isRawCoordinate(_ text: String, coordinate: GeoCoordinate) -> Bool {
        if text == coordinate.displayText || text == simplifiedCoordinate(coordinate) {
            return true
        }
        if case .coordinate = CoordinateTextParser.parse(text) {
            return true
        }
        return false
    }

    /// Extracts a concise street/road or area name from an international address string.
    private static func conciseAddressName(from address: String) -> String? {
        let segments = address
            .components(separatedBy: commaSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if segments.count > 1 {
            for segment in segments {
                let cleaned = AddressQuery.withoutPostalCode(segment) ?? segment
                if !isPostalCodeOnly(cleaned) {
                    return cleaned
                }
            }
        }

        let single = AddressQuery.withoutPostalCode(address) ?? address
        return single.isEmpty ? nil : single
    }

    private static func isPostalCodeOnly(_ segment: String) -> Bool {
        let stripped = segment
            .replacingOccurrences(of: "〒", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return true }
        // Numeric postal codes (e.g. 110, 95014, 100-0005, 75001)
        if stripped.allSatisfy({ $0.isASCIIDigit || $0 == "-" || $0 == " " }) {
            return true
        }
        // Short alphanumeric postal codes with digits (e.g. UK SW1A 2AA, Canada M5V 3L9)
        if stripped.count <= 10,
           stripped.contains(where: \.isASCIIDigit),
           stripped.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "-") }),
           stripped == stripped.uppercased() {
            return true
        }
        return false
    }

    private static func strippedGPXName(_ filename: String?) -> String? {
        guard let cleaned = normalizedLine(filename) else { return nil }
        if cleaned.lowercased().hasSuffix(".gpx") {
            let withoutExt = String(cleaned.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !withoutExt.isEmpty { return withoutExt }
        }
        return cleaned
    }

    private static func joinEndpoints(_ start: String, _ end: String) -> String {
        let separator = " → "
        let limit = FavoriteRoutesLimits.labelCharacters
        let combined = start + separator + end
        if combined.count <= limit { return combined }
        let sideBudget = max(1, (limit - separator.count) / 2)
        return clamped(start, limit: sideBudget) + separator + clamped(end, limit: sideBudget)
    }

    private static func clamped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 1 else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
