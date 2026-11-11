import Foundation

/// Address clean-up for a second search attempt when the pasted text finds nothing.
public enum AddressQuery {
    /// Leading postal codes that place search tends to treat as part of the name:
    /// Taiwan `337桃園市…` / `33743桃園市…` / `337001桃園市…`, Japan `〒060-0062 北海道…`.
    private static let leadingPostalCode = try! NSRegularExpression(
        pattern: #"^(?:〒\s*\d{3}-?\d{4}\s*|\d{3}(?:\d{2,3})?\s*(?=\p{Script=Han}))"#)

    /// The query without its leading postal code, or `nil` when nothing would change.
    public static func withoutPostalCode(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let stripped = leadingPostalCode.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty || stripped == trimmed ? nil : stripped
    }
}
