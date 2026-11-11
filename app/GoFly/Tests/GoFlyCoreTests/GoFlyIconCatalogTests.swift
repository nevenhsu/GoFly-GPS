import Foundation
import Testing

/// Keeps the Figma 04 vector exports and the single Swift catalog in lockstep.
struct GoFlyIconCatalogTests {
    private static let figmaIcons = [
        "alert", "arrow-right", "battery-full", "bookmark", "check", "chevron-down", "chevron-left",
        "chevron-right", "chevron-up", "close", "cloud-download", "copy", "direction-forward", "direction-reverse", "expand",
        "external-link", "flag", "gear", "globe", "grip", "help", "history", "hourglass", "joystick",
        "locate", "mac", "moon", "more", "nav", "paste", "pause", "phone", "pin", "play", "radius", "repeat",
        "repeat-off", "reset", "route", "route-folder", "route-list", "search", "select", "shield", "shuffle",
        "signal", "speed", "star", "star-filled", "stop", "success", "swap-horizontal", "swap-vertical",
        "terminal", "trash", "wifi"
    ]

    private static let figmaMapAndSpeedAssets = [
        "map-candidate-pin", "map-node-end", "map-node-start", "map-node-waypoint", "map-real-location",
        "map-sim-light", "map-sim-dark", "map-sim-light-wait", "map-sim-dark-wait",
        "speed-walk", "speed-bicycle", "speed-scooter", "speed-car"
    ]

    private static let figmaStatusToastAssets = ["danger", "warning", "success"]

    private struct AssetContents: Decodable {
        struct Appearance: Decodable { let appearance: String; let value: String }
        struct Image: Decodable { let filename: String; let appearances: [Appearance]? }
        struct Properties: Decodable {
            let templateRenderingIntent: String?
            let preservesVectorRepresentation: Bool?

            enum CodingKeys: String, CodingKey {
                case templateRenderingIntent = "template-rendering-intent"
                case preservesVectorRepresentation = "preserves-vector-representation"
            }
        }

        let images: [Image]
        let properties: Properties
    }

    private static func appRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() } // Tests/GoFlyCoreTests/<file> -> app/GoFly
        return url
    }

    @Test func everyFigmaIconHasATemplateVectorAndCatalogCase() throws {
        let assetRoot = Self.appRoot().appendingPathComponent("Resources/Assets.xcassets")
        let actualDirectories = try FileManager.default.contentsOfDirectory(atPath: assetRoot.path)
            .filter { $0.hasPrefix("icon-") && $0.hasSuffix(".imageset") }
            .map { String($0.dropLast(".imageset".count)) }
        let expectedDirectories = Self.figmaIcons.map { "icon-\($0)" }
        #expect(Set(actualDirectories) == Set(expectedDirectories))
        #expect(Self.figmaIcons.count == 56, "Figma 04 currently renders 56 icon/* assets (added icon/cloud-download)")

        let catalog = try String(contentsOf: Self.appRoot().appendingPathComponent("App/GoFlyIcon.swift"), encoding: .utf8)
        for icon in Self.figmaIcons {
            let assetName = "icon-\(icon)"
            let folder = assetRoot.appendingPathComponent("\(assetName).imageset")
            let contentsURL = folder.appendingPathComponent("Contents.json")
            let contents = try JSONDecoder().decode(AssetContents.self, from: Data(contentsOf: contentsURL))
            #expect(contents.images.first?.filename == "\(assetName).svg", "wrong SVG path for \(icon)")
            #expect(contents.properties.templateRenderingIntent == "template", "\(icon) is not a template asset")
            #expect(contents.properties.preservesVectorRepresentation == nil)
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(assetName).svg").path))
            #expect(catalog.contains("= \"icon/\(icon)\""), "GoFlyIcon is missing icon/\(icon)")
        }
    }

    @Test func mapAndSpeedArtworkUsesTheSameVectorEntryPoint() throws {
        let assetRoot = Self.appRoot().appendingPathComponent("Resources/Assets.xcassets")
        let catalog = try String(contentsOf: Self.appRoot().appendingPathComponent("App/GoFlyIcon.swift"), encoding: .utf8)
        for assetName in Self.figmaMapAndSpeedAssets {
            let folder = assetRoot.appendingPathComponent("\(assetName).imageset")
            let contents = try JSONDecoder().decode(AssetContents.self, from: Data(contentsOf: folder.appendingPathComponent("Contents.json")))
            #expect(contents.images.first?.filename == "\(assetName).svg")
            #expect(contents.properties.preservesVectorRepresentation == true)
            let resourcePath = assetName.hasPrefix("map-")
                ? "map/\(assetName.dropFirst("map-".count))"
                : "speed/\(assetName.dropFirst("speed-".count))"
            #expect(catalog.contains("= \"\(resourcePath)\""), "catalog is missing \(assetName)")
        }
    }

    @Test func statusToastGlyphsPreserveFigmaLightAndDarkArtwork() throws {
        let assetRoot = Self.appRoot().appendingPathComponent("Resources/Assets.xcassets")
        let catalog = try String(contentsOf: Self.appRoot().appendingPathComponent("App/GoFlyIcon.swift"), encoding: .utf8)
        for tone in Self.figmaStatusToastAssets {
            let assetName = "status-toast-\(tone)"
            let folder = assetRoot.appendingPathComponent("\(assetName).imageset")
            let contents = try JSONDecoder().decode(AssetContents.self, from: Data(contentsOf: folder.appendingPathComponent("Contents.json")))
            #expect(contents.properties.templateRenderingIntent == nil)
            #expect(contents.properties.preservesVectorRepresentation == true)
            #expect(Set(contents.images.compactMap { $0.appearances?.first?.value }) == Set(["light", "dark"]))
            for image in contents.images {
                #expect(image.appearances?.first?.appearance == "luminosity")
                #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(image.filename).path))
            }
            #expect(catalog.contains("= \"status-toast/\(tone)\""), "GoFlyIcon is missing \(assetName)")
        }
    }
}
