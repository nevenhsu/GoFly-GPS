import Foundation
import Testing
@testable import GoFlyCore

struct CoordinateTextParserTests {
    private func coordinate(_ text: String) -> GeoCoordinate? {
        if case .coordinate(let value) = CoordinateTextParser.parse(text) { return value }
        return nil
    }

    private func expectNear(_ text: String, _ latitude: Double, _ longitude: Double,
                            tolerance: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let value = coordinate(text) else {
            Issue.record("\(text) did not parse: \(CoordinateTextParser.parse(text))", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(value.latitude - latitude) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(value.longitude - longitude) < tolerance, sourceLocation: sourceLocation)
    }

    @Test func decimalPairs() {
        expectNear("25.0340, 121.5645", 25.0340, 121.5645)
        expectNear("25.0340,121.5645", 25.0340, 121.5645)
        expectNear("25.0340 121.5645", 25.0340, 121.5645)
        expectNear("(-31.8720065, 115.7526877)", -31.8720065, 115.7526877)
        expectNear("[-31.8720065, 115.7526877]", -31.8720065, 115.7526877)
        expectNear("25.0340，121.5645", 25.0340, 121.5645)
        expectNear("7, 11", 7, 11)
    }

    @Test func hemisphereDecimals() {
        expectNear("31.86650° S, 115.75419° E", -31.86650, 115.75419)
        expectNear("S 31.86650, E 115.75419", -31.86650, 115.75419)
        expectNear("115.75419° E, 31.86650° S", -31.86650, 115.75419)
        expectNear("40.7128° N 74.0060° W", 40.7128, -74.0060)
        expectNear("南緯 31.8665, 東經 115.7542", -31.8665, 115.7542)
    }

    @Test func degreesMinutesSeconds() {
        let latitude = -(31 + 51.0 / 60 + 49.7 / 3600)
        let longitude = 115 + 45.0 / 60 + 7.0 / 3600
        expectNear(#"31°51'49.7"S 115°45'07.0"E"#, latitude, longitude)
        // iOS smart punctuation turns ' and " into curly quotes.
        expectNear("31°51’49.7”S 115°45’07.0”E", latitude, longitude)
        expectNear("31°51′49.7″S 115°45′07.0″E", latitude, longitude)
        expectNear("31°51.828'S 115°45.117'E", -(31 + 51.828 / 60), 115 + 45.117 / 60)
    }

    @Test func rangeAndFormatErrors() {
        #expect(CoordinateTextParser.parse("91, 121") == .invalid(.latitudeRange))
        #expect(CoordinateTextParser.parse("25, 181") == .invalid(.longitudeRange))
        #expect(CoordinateTextParser.parse("25,121,3") == .invalid(.format))
        #expect(CoordinateTextParser.parse("25°61'S 121°E") == .invalid(.format))
        #expect(CoordinateTextParser.parse("25 N, 121 N") == .invalid(.format))
        #expect(CoordinateTextParser.parse("-25 N, 121 E") == .invalid(.format))
    }

    @Test func addressesAndNamesAreNotCoordinates() {
        for text in [
            "6 Chome-1-1 Minami 2 Jonishi, Chuo Ward, Sapporo, Hokkaido 060-0062日本",
            "337桃園市大園區圳頭里西部濱海公路76號",
            "4QM3+M6 North Beach, 西澳大利亞州澳洲",
            "1600 Amphitheatre Pkwy, Mountain View",
            "taipei 101", "101", "7 11", "News",
        ] {
            #expect(CoordinateTextParser.parse(text) == .notCoordinate, "\(text)")
        }
    }
}

struct OpenLocationCodeTests {
    @Test func classifiesCodes() {
        #expect(OpenLocationCode.classify("8FVC9G8F+6X")?.kind == .full)
        #expect(OpenLocationCode.classify("4qm3+m6")?.kind == .short)
        #expect(OpenLocationCode.classify("22+") == nil)
        #expect(OpenLocationCode.classify("4QM3+M") == nil)
        #expect(OpenLocationCode.classify("ABCD+EF") == nil)
    }

    @Test func decodesFullCode() throws {
        // 8FVC9G8F+6X covers 47.3655–47.3656 N, 8.52487–8.52500 E; its centre is 47.3655625, 8.5249375.
        let value = try #require(OpenLocationCode.decode("8FVC9G8F+6X"))
        #expect(abs(value.latitude - 47.3655625) < 1e-9)
        #expect(abs(value.longitude - 8.5249375) < 1e-9)
    }

    @Test func recoversShortCodeNearReference() throws {
        let full = try #require(OpenLocationCode.decode("8FVC9G8F+6X"))
        let reference = try #require(GeoCoordinate(latitude: 47.4, longitude: 8.6))
        let recovered = try #require(OpenLocationCode.recoverNearest("9G8F+6X", reference: reference))
        #expect(abs(recovered.latitude - full.latitude) < 1e-9)
        #expect(abs(recovered.longitude - full.longitude) < 1e-9)
    }

    @Test func recoversAcrossCellBoundary() throws {
        // The reference's own 1° cell gives 47.3656 (0.62° away); the next cell up is nearer.
        let reference = try #require(GeoCoordinate(latitude: 47.99, longitude: 8.5))
        let recovered = try #require(OpenLocationCode.recoverNearest("9G8F+6X", reference: reference))
        #expect(abs(recovered.latitude - 48.3655625) < 1e-9)
        #expect(abs(recovered.longitude - 8.5249375) < 1e-9)
    }

    @Test func recoversPerthExample() throws {
        // North Beach, Western Australia.
        let reference = try #require(GeoCoordinate(latitude: -31.863, longitude: 115.756))
        let recovered = try #require(OpenLocationCode.recoverNearest("4QM3+M6", reference: reference))
        #expect(abs(recovered.latitude - -31.8658125) < 1e-6)
        #expect(abs(recovered.longitude - 115.7530625) < 1e-6)
    }

    @Test func parsesQueryWithLocality() {
        let query = PlusCodeQuery("4QM3+M6 North Beach, 西澳大利亞州澳洲")
        #expect(query?.code == "4QM3+M6")
        #expect(query?.kind == .short)
        #expect(query?.locality == "North Beach, 西澳大利亞州澳洲")
        #expect(PlusCodeQuery("8FVC9G8F+6X")?.locality == nil)
        #expect(PlusCodeQuery("taipei 101") == nil)
    }
}

struct AddressQueryTests {
    @Test func stripsLeadingPostalCodes() {
        #expect(AddressQuery.withoutPostalCode("337桃園市大園區圳頭里西部濱海公路76號") == "桃園市大園區圳頭里西部濱海公路76號")
        #expect(AddressQuery.withoutPostalCode("33743 桃園市大園區") == "桃園市大園區")
        #expect(AddressQuery.withoutPostalCode("〒060-0062 北海道札幌市") == "北海道札幌市")
        #expect(AddressQuery.withoutPostalCode("台北101") == nil)
        #expect(AddressQuery.withoutPostalCode("1600 Amphitheatre Pkwy") == nil)
    }
}

@MainActor
struct CandidateControllerQueryTests {
    private struct Fixed: PlaceSearching {
        let places: [MapPlace]
        func search(query: String) async throws -> [MapPlace] { places }
    }

    @Test func numericLeadingAddressSearchesByName() {
        let search = CandidateController(search: Fixed(places: []), debounce: .seconds(60))
        search.updateQuery("6 Chome-1-1 Minami 2 Jonishi, Chuo Ward, Sapporo")
        #expect(search.queryKind == .name)
        #expect(search.inputError == nil)
    }

    @Test func formattedCoordinateCreatesCandidate() {
        let search = CandidateController(search: Fixed(places: []), debounce: .seconds(60))
        search.updateQuery(#"31°51'49.7"S 115°45'07.0"E"#)
        #expect(search.queryKind == .coordinate)
        #expect(search.canGo)
    }

    @Test func fullPlusCodeCreatesCandidate() {
        let search = CandidateController(search: Fixed(places: []), debounce: .seconds(60))
        search.updateQuery("8FVC9G8F+6X")
        #expect(search.queryKind == .coordinate)
        #expect(search.canGo)
    }

    @Test func shortPlusCodeResolvesAgainstLocality() async throws {
        let anchor = try #require(GeoCoordinate(latitude: -31.863, longitude: 115.756))
        let search = CandidateController(
            search: Fixed(places: [MapPlace(id: .coordinate(anchor), title: "North Beach", coordinate: anchor)]),
            debounce: .zero)
        search.updateQuery("4QM3+M6 North Beach, 西澳大利亞州澳洲")
        #expect(search.queryKind == .name)
        while search.isSearching { try await Task.sleep(for: .milliseconds(10)) }
        let place = try #require(search.results.first)
        #expect(abs(place.coordinate.latitude - -31.8658125) < 1e-6)
        #expect(place.title == "4QM3+M6 North Beach, 西澳大利亞州澳洲")
    }
}

struct MapLinkParserTests {
    private func point(_ text: String) -> (GeoCoordinate, String?)? {
        if case .coordinate(let value, let title)? = MapLinkParser.parse(text) { return (value, title) }
        return nil
    }

    @Test func googlePlaceLinkUsesDataPinAndName() throws {
        let link = "https://www.google.com/maps/place/South+San+Francisco,+CA,+USA/@37.653621,-122.3461976,10z/data=!4m6!3m5!1s0x808f790543feecef:0xf83a7579e756335d!8m2!3d37.654656!4d-122.4077498!16zL20vMHI1eXA?g_ep=Eg1tbF8yMDI2MTEwOF8wIJvbDyoASAJQAg%3D%3D"
        let (coordinate, title) = try #require(point(link))
        #expect(coordinate.latitude == 37.654656)
        #expect(coordinate.longitude == -122.4077498)
        #expect(title == "South San Francisco, CA, USA")
    }

    @Test func googleLinkVariants() throws {
        #expect(point("https://www.google.com/maps/@25.0339639,121.5644722,17z")?.0.latitude == 25.0339639)
        #expect(point("https://www.google.com/maps/search/25.033964,+121.564472")?.0.longitude == 121.564472)
        #expect(point("https://maps.google.com/?q=25.033964,121.564472")?.0.latitude == 25.033964)
        #expect(point("https://www.google.com/maps/search/?api=1&query=25.03,121.56")?.0.latitude == 25.03)
        #expect(point("https://www.google.com.tw/maps?q=loc:25.03,121.56")?.0.latitude == 25.03)
        #expect(point("google.com/maps/@25.03,121.56,15z")?.0.longitude == 121.56)
    }

    @Test func googleRedirectTargetWithPlaceName() {
        let link = "https://maps.google.com?q=%E7%BE%8E%E5%9C%8B%E5%8A%A0%E5%88%A9%E7%A6%8F%E5%B0%BC%E4%BA%9E%E5%8D%97%E8%88%8A%E9%87%91%E5%B1%B1&ftid=0x808f790543feecef:0xf83a7579e756335d&entry=gps&g_st=ic"
        #expect(MapLinkParser.parse(link) == .text("美國加利福尼亞南舊金山"))
    }

    @Test func googleDirectionsUseDestination() {
        #expect(MapLinkParser.parse("https://www.google.com/maps/dir/Taipei+Main+Station/Taipei+101/@25.04,121.53,13z")
                == .text("Taipei 101"))
    }

    @Test func applePlaceLinks() throws {
        let unified = try #require(point("https://maps.apple.com/place?coordinate=25.033964,121.564472&name=Taipei%20101"))
        #expect(unified.0.latitude == 25.033964)
        #expect(unified.1 == "Taipei 101")
        #expect(point("https://maps.apple.com/?ll=25.03,121.56&q=Dropped%20Pin")?.0.longitude == 121.56)
        #expect(MapLinkParser.parse("https://maps.apple.com/?address=No.%207,%20Section%205,%20Xinyi%20Road,%20Taipei")
                == .text("No. 7, Section 5, Xinyi Road, Taipei"))
    }

    @Test func appleShortLinkRedirectTarget() throws {
        // Location header returned for https://maps.apple/p/DjH-EsP-xN_7n_ (2026-11-11).
        let link = "https://maps.apple.com/place?address=No.%20340%20Zhongzheng%20E%20Rd,%20Dayuan%20District,%20Taoyuan%20City%20337,%20Taiwan&coordinate=25.060172,121.207763&name=CPC&place-id=I9C402B051678C696&map=explore"
        let (coordinate, title) = try #require(point(link))
        #expect(coordinate.latitude == 25.060172)
        #expect(coordinate.longitude == 121.207763)
        #expect(title == "CPC")
        #expect(MapLinkParser.shortLink("https://maps.apple/p/DjH-EsP-xN_7n_") != nil)
    }

    @Test func geoURIs() throws {
        #expect(point("geo:25.03,121.56")?.0.latitude == 25.03)
        let labelled = try #require(point("geo:0,0?q=25.03,121.56(Taipei 101)"))
        #expect(labelled.1 == "Taipei 101")
        #expect(MapLinkParser.parse("geo:0,0?q=Taipei+101") == .text("Taipei 101"))
    }

    @Test func shortLinksNeedExpansion() {
        #expect(MapLinkParser.parse("https://maps.app.goo.gl/CS9AF4nW5cAtPZG66?g_st=ic") == nil)
        #expect(MapLinkParser.shortLink("https://maps.app.goo.gl/CS9AF4nW5cAtPZG66?g_st=ic") != nil)
        #expect(MapLinkParser.shortLink("https://goo.gl/maps/abc123") != nil)
        #expect(MapLinkParser.shortLink("https://example.com/maps/abc") == nil)
        #expect(MapLinkParser.parse("taipei101") == nil)
        #expect(MapLinkParser.parse("https://example.com/maps/@25.03,121.56,15z") == nil)
    }
}

@MainActor
struct CandidateControllerLinkTests {
    private struct Echo: PlaceSearching {
        func search(query: String) async throws -> [MapPlace] {
            let coordinate = GeoCoordinate(latitude: 37.65, longitude: -122.41)!
            return [MapPlace(id: .coordinate(coordinate), title: query, coordinate: coordinate)]
        }
    }

    private struct FixedExpander: MapLinkExpanding {
        let target: URL?
        func expand(_ shortLink: URL) async throws -> URL? { target }
    }

    @Test func pastedPlaceLinkCreatesNamedCandidate() {
        let search = CandidateController(search: Echo(), debounce: .seconds(60))
        search.updateQuery("https://www.google.com/maps/place/Taipei+101/@25.03,121.56,17z/data=!3d25.0339639!4d121.5644722")
        #expect(search.queryKind == .coordinate)
        #expect(search.results.first?.title == "Taipei 101")
        #expect(search.canGo)
    }

    @Test func shortLinkSearchesExpandedPlaceName() async throws {
        let expanded = URL(string: "https://maps.google.com?q=South+San+Francisco&ftid=0x1:0x2")
        let search = CandidateController(search: Echo(), linkExpander: FixedExpander(target: expanded), debounce: .zero)
        search.updateQuery("https://maps.app.goo.gl/CS9AF4nW5cAtPZG66?g_st=ic")
        #expect(search.queryKind == .name)
        while search.isSearching { try await Task.sleep(for: .milliseconds(10)) }
        #expect(search.results.first?.title == "South San Francisco")
    }
}
