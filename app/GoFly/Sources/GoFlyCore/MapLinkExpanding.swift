import Foundation

/// Follows a short map share link (see `MapLinkParser.shortLink(_:)`) to the full link it redirects to.
public protocol MapLinkExpanding: Sendable {
    /// The expanded link, or `nil` when the service did not redirect to a map link.
    func expand(_ shortLink: URL) async throws -> URL?
}
