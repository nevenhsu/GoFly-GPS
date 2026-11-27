import Foundation
import Testing
@testable import GoFlyCore
@Suite @MainActor struct PersistenceTests {
    @Test func favoritePlaceDefaultNameSupportsInternationalPlacesAddressesAndSimplifiedCoordinates() throws {
        let taipei = try #require(GeoCoordinate(latitude: 25.033964, longitude: 121.564468))
        let poi = MapPlace(id: .mapKit("poi"), title: "台北 101", coordinate: taipei, address: "110台灣台北市信義區信義路五段7號")
        #expect(FavoriteLabelDefaults.defaultName(for: poi) == "台北 101")

        let usAddress = MapPlace(
            id: .coordinate(taipei),
            title: "1 Apple Park Way, Cupertino, CA 95014, United States",
            coordinate: taipei,
            address: "1 Apple Park Way, Cupertino, CA 95014, United States"
        )
        #expect(FavoriteLabelDefaults.defaultName(for: usAddress) == "1 Apple Park Way")

        let jpAddress = MapPlace(
            id: .coordinate(taipei),
            title: "〒100-0005 日本東京都千代田区丸の内",
            coordinate: taipei,
            address: "〒100-0005 日本東京都千代田区丸の内"
        )
        #expect(FavoriteLabelDefaults.defaultName(for: jpAddress) == "日本東京都千代田区丸の内")

        let ukPostalFirst = MapPlace(
            id: .coordinate(taipei),
            title: taipei.displayText,
            coordinate: taipei,
            address: "SW1A 2AA, 10 Downing Street, London, United Kingdom"
        )
        #expect(FavoriteLabelDefaults.defaultName(for: ukPostalFirst) == "10 Downing Street")

        let ocean = MapPlace(id: .coordinate(taipei), title: taipei.displayText, coordinate: taipei)
        #expect(FavoriteLabelDefaults.defaultName(for: ocean) == "25.0340, 121.5645")

        let fallback = FavoriteLabelDefaults.defaultName(for: poi)
        #expect(FavoriteLabelDefaults.resolved(" \n\t", fallback: fallback) == "台北 101")
        #expect(FavoriteLabelDefaults.resolved("Weekend route", fallback: fallback) == "Weekend route")
    }

    @Test func favoriteRouteDefaultNameUsesGPXFilenameOrEndpoints() throws {
        let start = try #require(GeoCoordinate(latitude: 25.0478, longitude: 121.5170))
        let end = try #require(GeoCoordinate(latitude: 25.1678, longitude: 121.4456))
        let manual = try FavoriteRouteRecord(
            id: UUID(), label: nil, sourceKind: .manual, count: 2,
            start: start, end: end, startTitle: "台北車站", endTitle: "淡水老街",
            displayFilename: nil, byteCount: 64, sha256: String(repeating: "a", count: 64)
        )
        #expect(FavoriteLabelDefaults.defaultName(for: manual) == "台北車站 → 淡水老街")

        let coordManual = try FavoriteRouteRecord(
            id: UUID(), label: nil, sourceKind: .manual, count: 2,
            start: start, end: end, startTitle: start.displayText, endTitle: end.displayText,
            displayFilename: nil, byteCount: 64, sha256: String(repeating: "b", count: 64)
        )
        #expect(FavoriteLabelDefaults.defaultName(for: coordManual) == "25.0478, 121.5170 → 25.1678, 121.4456")

        let gpx = try FavoriteRouteRecord(
            id: UUID(), label: nil, sourceKind: .gpx, count: 12,
            start: start, end: end, startTitle: nil, endTitle: nil,
            displayFilename: "Morning Walk.gpx", byteCount: 64, sha256: String(repeating: "c", count: 64)
        )
        #expect(FavoriteLabelDefaults.defaultName(for: gpx) == "Morning Walk")
    }

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/gofly-c3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func favoritePlacesReadsTheExistingSchemaOneFileUnchanged() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = Data(#"{"schemaVersion":1,"favorites":[{"identity":{"kind":"coordinate","value":null},"coordinate":{"latitude":25,"longitude":121},"title":"25.000000, 121.000000","address":null,"label":"home"}]}"#.utf8)
        try old.write(to: root.appendingPathComponent("favorites.json"))
        let disk = FileFavoritePlacesPersistence(directory: root)
        let data = try #require(try disk.read())
        #expect(data == old)
        let favorites = try FavoritePlacesArchive.decode(data)
        #expect(favorites.count == 1)
        #expect(favorites[0].label == "home")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["favorites.json"])
    }
    @Test func sessionReadsTheExistingSchemaOneFileUnchanged() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = Data(#"{"activeMovement":null,"draft":{"gpxData":null,"gpxFilename":null,"nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"current","place":null}],"sourceKind":"manual","speed":20},"joystickSpeed":20,"mode":"teleport","position":{"coordinate":{"latitude":25,"longitude":121},"source":"gps"},"revision":9,"roundTripEnabled":false,"schemaVersion":1,"uncertainty":null}"#.utf8)
        try old.write(to: root.appendingPathComponent("session.json"))
        let data = try #require(try FileSessionRecoveryPersistence(directory: root).read())
        #expect(data == old)
        #expect(try SessionRecoveryCodec.decodeRecord(data).revision == 9)
    }
    @Test func oldSessionColdFieldsAreIgnoredInsteadOfCorrupting() throws {
        let old = Data(#"{"activeMovement":null,"coldRecoveryHeld":true,"draft":{"gpxData":null,"gpxFilename":null,"nodes":[],"sourceKind":"manual","speed":20},"joystickSpeed":20,"mode":"teleport","position":null,"requiresColdConfirmation":true,"revision":4,"roundTripEnabled":false,"schemaVersion":1,"uncertainty":null}"#.utf8)
        let record = try SessionRecoveryCodec.decodeRecord(old)
        #expect(record.revision == 4)
        #expect(record.snapshot.mode == .teleport)
    }
    @Test func favoritePlacesRoundTripKeepsPrivatePermissions() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let disk = FileFavoritePlacesPersistence(directory: root)
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        let store = FavoritePlacesStore(persistence: disk)
        #expect(store.toggle(place))
        let data = try #require(try disk.read())
        #expect(try FavoritePlacesArchive.decode(data).count == 1)
        #expect((try FileManager.default.attributesOfItem(atPath: disk.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
    @Test func favoritePlacesBatchDeleteUndoPreservesOrderAndLabels() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let disk = FileFavoritePlacesPersistence(directory: root)
        let store = FavoritePlacesStore(persistence: disk)
        let places = (0..<3).map { index in
            let coordinate = GeoCoordinate(latitude: 25 + Double(index), longitude: 121)!
            return MapPlace(id: .coordinate(coordinate), title: "Place \(index)", coordinate: coordinate)
        }
        for place in places { #expect(store.toggle(place)) }
        let keys = places.map { FavoritePlaceKey(place: $0)! }
        #expect(store.saveLabel(for: keys[0], draft: "Home"))
        #expect(store.saveLabel(for: keys[2], draft: "Office"))
        let original = store.favorites
        #expect(store.delete([keys[0], keys[2]]))
        #expect(store.favorites.map(\.key) == [keys[1]])
        #expect(store.undoDelete())
        #expect(store.favorites == original)
        #expect(FavoritePlacesStore(persistence: disk).favorites == original)
        #expect(!store.canUndo)
    }
    @Test func corruptFavoritePlacesBlocksMutationAndKeepsTheOriginalBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("favorites.json")
        let corrupt = Data(#"{"schemaVersion":1,"favorites":"not-an-array"}"#.utf8)
        try corrupt.write(to: file)
        let store = FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: root))
        #expect(store.loadState == .blocked(.corruptArchive))
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        #expect(!store.toggle(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)))
        #expect(try Data(contentsOf: file) == corrupt)
    }
    @Test func importedRouteExportsOriginalXMLBytesAfterReload() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:custom="urn:gofly:test" version="1.1" creator="Source App">
          <metadata><name>Morning route</name></metadata>
          <trk><name>River walk</name><trkseg>
            <trkpt lat="25.000000" lon="121.000000"><ele>8.25</ele><time>2026-10-20T01:00:00Z</time></trkpt>
            <trkpt lat="25.001000" lon="121.001000"><ele>9.50</ele><time>2026-10-20T01:01:00Z</time></trkpt>
          </trkseg><extensions><custom:note>Keep this metadata</custom:note></extensions></trk>
        </gpx>
        """.utf8)
        let store = ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: root))
        await store.load()
        #expect(await store.importData(original, filename: "source.gpx"))
        let record = try #require(store.records.first)
        #expect(record.byteCount == original.count)
        #expect(record.sha256 == ImportedRouteArtifact.hash(original))
        let reloaded = ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: root))
        await reloaded.load()
        await reloaded.select(record.id)
        #expect(reloaded.selectedSnapshot?.document.pointCount == 2)
        #expect(try await reloaded.exportSelected() == original)
    }
    @Test func importedRouteDeleteAndUndoAreStoreMemoryOnly() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let disk = FileImportedRoutesPersistence(directory: root)
        let artifact = try importedArtifact()
        _ = try await disk.importArtifact(artifact)
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        let record = try #require(store.records.first)
        #expect(await store.delete(record.id))
        #expect(store.canUndo)
        #expect(store.records.isEmpty)
        let relaunched = ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: root))
        await relaunched.load()
        #expect(!relaunched.canUndo)
        #expect(await store.undoDelete())
        #expect(store.records.map(\.id) == [record.id])
        #expect(!store.canUndo)
    }
    @Test func corruptManifestBlocksReadAndMutationWithoutRewriting() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("manifest.json")
        let corrupt = Data(#"{"schemaVersion":99,"records":[]}"#.utf8)
        try corrupt.write(to: manifest)
        let store = ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: root))
        await store.load()
        #expect(store.loadState == .blocked(.unsupportedSchema))
        #expect(!store.canMutate)
        #expect(try Data(contentsOf: manifest) == corrupt)
    }
    @Test func missingPayloadIsUnavailableAndNeverRemovedFromTheManifest() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let disk = FileImportedRoutesPersistence(directory: root)
        let artifact = try importedArtifact()
        let receipt = try await disk.importArtifact(artifact)
        let record = try #require(receipt.records.first)
        try FileManager.default.removeItem(at: root.appendingPathComponent(record.id.uuidString + ".gpx"))
        let reread = try await disk.read()
        #expect(reread.records.map(\.id) == [record.id])
        #expect(reread.unavailable[record.id] == .unavailable)
        #expect(try Data(contentsOf: root.appendingPathComponent("manifest.json")).isEmpty == false)
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        await store.select(record.id)
        #expect(store.unavailable[record.id] == .unavailable)
        #expect(await store.delete(record.id))
        #expect(try await disk.read().records.isEmpty)
    }
    @Test func favoriteRoutesBatchDeleteAndUndo() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: root))
        await store.load()
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let c = GeoCoordinate(latitude: 25.02, longitude: 121.02)!
        let candidate1 = FavoriteRouteSaveCandidate(source: .manual([
            MapPlace(id: .coordinate(a), title: "Point A", coordinate: a),
            MapPlace(id: .coordinate(b), title: "Point B", coordinate: b)
        ]), omittedUnavailableCurrent: false)
        let candidate2 = FavoriteRouteSaveCandidate(source: .manual([
            MapPlace(id: .coordinate(b), title: "Point B", coordinate: b),
            MapPlace(id: .coordinate(c), title: "Point C", coordinate: c)
        ]), omittedUnavailableCurrent: false)
        let res1 = try #require(await store.save(candidate1, label: "Route 1"))
        let res2 = try #require(await store.save(candidate2, label: "Route 2"))
        #expect(store.records.count == 2)
        let ids = Set([res1.record.id, res2.record.id])
        #expect(await store.delete(ids))
        #expect(store.records.isEmpty)
        #expect(store.canUndo)
        #expect(await store.undoDelete())
        #expect(store.records.count == 2)
        #expect(!store.canUndo)
    }
    private func importedArtifact() throws -> ImportedRouteArtifact {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 25.001, longitude: 121.001)!
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[a, b]])]))
        return try ImportedRouteArtifact(document: document, filename: "fixture.gpx")
    }
}
