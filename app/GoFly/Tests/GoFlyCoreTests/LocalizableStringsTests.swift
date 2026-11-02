import Foundation
import Testing
@testable import GoFlyCore

/// A malformed .strings file silently drops every key after the error, so each
/// language must parse and carry the same keys.
struct LocalizableStringsTests {
    private static func load(_ language: String) throws -> [String: String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }   // Tests/GoFlyCoreTests/<file> -> app/GoFly
        let data = try Data(contentsOf: url.appendingPathComponent("Resources/\(language).lproj/Localizable.strings"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func everyLanguageParsesAndHasTheSameKeys() throws {
        let en = try Self.load("en")
        for language in ["zh-Hant", "zh-Hans"] {
            let other = try Self.load(language)
            #expect(Set(other.keys).symmetricDifference(Set(en.keys)).isEmpty,
                    "\(language) differs from en: \(Set(other.keys).symmetricDifference(Set(en.keys)).sorted())")
        }
    }

    /// Every toast is title + second line: each error key needs its title copy.
    @Test func everyToastKeyHasATitle() throws {
        let en = try Self.load("en")
        let toastKeys = en.keys.filter { key in
            ["error.", "route.error.", "imports.execution.", "joystick.error.", "favorites.error.", "imports.error.",
             "favoriteRoutes.error.", "gpx.error.", "recovery.error.", "wander.error."]
                .contains { key.hasPrefix($0) } && !key.hasSuffix(".title") && !key.hasSuffix(".shortTitle")
        } + ["search.pasteInvalidCoordinate", "search.pastePlaceNotFound", "search.pasteSearchFailed", "search.coordinateFormat", "search.latitudeRange", "search.longitudeRange", "settings.externalOpenFailed",
             "onboarding.vpn.externalOpenFailed", "setup.pairingImport.failed", "favoriteRoutes.savedOmittingCurrent"]
        for key in toastKeys {
            #expect(en[IssueCatalog.titleKey(for: key)] != nil, "\(key) has no title \(IssueCatalog.titleKey(for: key))")
        }
    }
}
