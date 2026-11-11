import Combine
import Foundation

public protocol PlaceSearching: Sendable {
    func search(query: String) async throws -> [MapPlace]
}

public enum CoordinateInputFailure: String, Equatable, Sendable {
    case format = "search.coordinateFormat"
    case latitudeRange = "search.latitudeRange"
    case longitudeRange = "search.longitudeRange"
}

public enum PlaceQueryKind: Equatable, Sendable { case empty, name, coordinate, invalidCoordinate }

@MainActor
public final class CandidateController: ObservableObject {
    @Published public private(set) var query = ""
    @Published public private(set) var queryKind: PlaceQueryKind = .empty
    @Published public private(set) var results: [MapPlace] = []
    @Published public private(set) var candidate: TeleportCandidate?
    @Published public private(set) var inputError: CoordinateInputFailure?
    @Published public private(set) var isSearching = false
    @Published public private(set) var searchFailed = false
    private var blockedByInvalidInput = false
    private var blockedByUnselectedNameQuery = false
    private let search: any PlaceSearching
    private let linkExpander: (any MapLinkExpanding)?
    private let debounce: Duration
    private var revision: UInt64 = 0
    private var searchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    public init(search: any PlaceSearching, linkExpander: (any MapLinkExpanding)? = nil,
                debounce: Duration = .milliseconds(300)) {
        self.search = search
        self.linkExpander = linkExpander
        self.debounce = debounce
    }
    deinit { searchTask?.cancel(); metadataTask?.cancel() }
    public var canGo: Bool { candidate != nil && !blockedByInvalidInput && !blockedByUnselectedNameQuery }
    var editingRevision: UInt64 { revision }
    public func updateQuery(_ text: String) {
        // A text field re-sends its unchanged text when it loses focus or
        // commits marked text; that is not an edit and must keep the selection.
        guard text != query else { return }
        cancelSearch()
        query = text
        inputError = nil
        searchFailed = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shortLink = MapLinkParser.shortLink(trimmed), let linkExpander {
            // A share link names no place until it is expanded; treat it like a name search.
            queryKind = .name
            blockedByUnselectedNameQuery = true
            results = []
            searchShortLink(shortLink, expander: linkExpander)
            return
        }
        switch MapLinkParser.parse(trimmed) {
        case .coordinate(let coordinate, let title)?:
            acceptCoordinate(coordinate, title: title)
        case .text(let linkText)?:
            classify(linkText.trimmingCharacters(in: .whitespacesAndNewlines))
        case nil:
            classify(trimmed)
        }
    }

    /// Plus Code first, then coordinate notations, otherwise a name or address search.
    private func classify(_ trimmed: String) {
        if let plusCode = PlusCodeQuery(trimmed) {
            if plusCode.kind == .full, let coordinate = OpenLocationCode.decode(plusCode.code) {
                acceptCoordinate(coordinate)
                return
            }
            if plusCode.kind == .short, let locality = plusCode.locality {
                // The locality anchors the short code; the result still needs an explicit selection.
                queryKind = .name
                blockedByUnselectedNameQuery = true
                results = []
                recoverPlusCode(plusCode.code, near: locality, title: trimmed)
                return
            }
        }
        switch CoordinateTextParser.parse(trimmed) {
        case .coordinate(let coordinate):
            acceptCoordinate(coordinate)
        case .invalid(let failure):
            rejectCoordinates(failure)
        case .notCoordinate:
            queryKind = trimmed.isEmpty ? .empty : .name
            blockedByUnselectedNameQuery = !trimmed.isEmpty
            results = []
            if !trimmed.isEmpty { searchNames(trimmed) }
        }
    }

    private func acceptCoordinate(_ coordinate: GeoCoordinate, title: String? = nil) {
        let place = MapPlace(id: .coordinate(coordinate), title: title ?? coordinate.displayText, coordinate: coordinate)
        queryKind = .coordinate
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        results = [place]
        candidate = TeleportCandidate(place: place)
    }

    private func rejectCoordinates(_ failure: CoordinateInputFailure) {
        queryKind = .invalidCoordinate
        inputError = failure
        blockedByInvalidInput = true
        results = []
    }
    public func select(_ place: MapPlace) {
        cancelSearch()
        if queryKind == .invalidCoordinate {
            query = place.coordinate.displayText
            queryKind = .coordinate
            results = [place]
        }
        if results.isEmpty { results = [place] }
        inputError = nil
        searchFailed = false
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        candidate = TeleportCandidate(place: place)
    }
    public func selectMapCoordinate(_ coordinate: GeoCoordinate, resolver: (any PlaceResolving)? = nil) {
        cancelSearch()
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        query = coordinate.displayText
        queryKind = .coordinate
        results = [place]
        inputError = nil
        searchFailed = false
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        let selected = TeleportCandidate(place: place)
        candidate = selected
        if let resolver { resolveMetadata(at: coordinate, candidateID: selected.id, resolver: resolver) }
    }
    public func clearCandidate(ifMatching id: UUID) {
        guard candidate?.id == id else { return }
        candidate = nil
    }
    public func resetSelection() {
        cancelSearch()
        query = ""; queryKind = .empty; results = []; candidate = nil
        inputError = nil; searchFailed = false
        blockedByInvalidInput = false; blockedByUnselectedNameQuery = false
    }
    func cancelPendingLookups() { cancelSearch() }

    private func cancelSearch() {
        revision &+= 1
        searchTask?.cancel()
        searchTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        isSearching = false
    }

    private func resolveMetadata(at coordinate: GeoCoordinate, candidateID: UUID, resolver: any PlaceResolving) {
        let token = revision
        metadataTask = Task { [weak self] in
            do {
                guard let resolved = try await resolver.resolve(at: coordinate) else { return }
                try Task.checkCancellation()
                guard let self, self.revision == token, self.candidate?.id == candidateID,
                      self.candidate?.place.coordinate == coordinate else { return }
                let refined = MapPlace(id: .coordinate(coordinate), title: resolved.title,
                    coordinate: coordinate, address: resolved.address)
                self.query = refined.title
                self.queryKind = refined.title == coordinate.displayText ? .coordinate : .name
                self.results = [refined]
                self.candidate = TeleportCandidate(id: candidateID, place: refined)
            } catch {
                // Optional display metadata cannot invalidate an exact, explicitly selected map point.
            }
        }
    }

    private func searchNames(_ query: String) {
        let search = search
        runSearch { try await search.search(query: query) }
    }

    /// Looks up the locality, then recovers the short code nearest to its first result.
    private func recoverPlusCode(_ code: String, near locality: String, title: String) {
        let search = search
        runSearch { try await Self.recoverPlusCode(code, near: locality, title: title, search: search) }
    }

    nonisolated private static func recoverPlusCode(_ code: String, near locality: String, title: String,
                                                    search: any PlaceSearching) async throws -> [MapPlace] {
        guard let anchor = try await search.search(query: locality).first,
              let coordinate = OpenLocationCode.recoverNearest(code, reference: anchor.coordinate) else { return [] }
        return [MapPlace(id: .coordinate(coordinate), title: title, coordinate: coordinate)]
    }

    private func searchShortLink(_ link: URL, expander: any MapLinkExpanding) {
        let search = search
        runSearch {
            guard let expanded = try await expander.expand(link),
                  let target = MapLinkParser.parse(expanded.absoluteString) else { return [] }
            try Task.checkCancellation()
            return try await Self.places(for: target, search: search)
        }
    }

    /// The places an expanded link points to, using the same rules as typed text.
    nonisolated private static func places(for target: MapLinkParser.Target,
                                           search: any PlaceSearching) async throws -> [MapPlace] {
        switch target {
        case .coordinate(let coordinate, let title):
            return [MapPlace(id: .coordinate(coordinate), title: title ?? coordinate.displayText, coordinate: coordinate)]
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let plusCode = PlusCodeQuery(trimmed) {
                if plusCode.kind == .full, let coordinate = OpenLocationCode.decode(plusCode.code) {
                    return [MapPlace(id: .coordinate(coordinate), title: trimmed, coordinate: coordinate)]
                }
                if plusCode.kind == .short, let locality = plusCode.locality {
                    return try await recoverPlusCode(plusCode.code, near: locality, title: trimmed, search: search)
                }
            }
            if case .coordinate(let coordinate) = CoordinateTextParser.parse(trimmed) {
                return [MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)]
            }
            return trimmed.isEmpty ? [] : try await search.search(query: trimmed)
        }
    }

    private func runSearch(_ operation: @escaping @Sendable () async throws -> [MapPlace]) {
        isSearching = true
        let token = revision
        let debounce = debounce
        searchTask = Task { [weak self] in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                try Task.checkCancellation()
                let places = try await operation()
                try Task.checkCancellation()
                guard let self, self.revision == token else { return }
                self.results = places
                self.isSearching = false
            } catch {
                guard let self, self.revision == token else { return }
                self.isSearching = false
                self.searchFailed = !(error is CancellationError)
                self.results = []
            }
        }
    }
}
