import Foundation
import Testing
import GoFlyMacCore

@Suite struct MacBundleResourcesTests {
    private func makeBundle(at root: URL) throws -> (URL, URL) {
        let resources = root.appendingPathComponent("GoFly.app/Contents/Resources", isDirectory: true)
        let developer = root.appendingPathComponent("Xcode.app/Contents/Developer", isDirectory: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Bridge"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Python/python/install/bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("SigningStub/GoFly.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Bridge/Device"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Bridge/Setup"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Python/python/install/lib/python3.14/site-packages"), withIntermediateDirectories: true)
        try Data("# bridge".utf8).write(to: resources.appendingPathComponent("Bridge/bridge.py"))
        for path in ["Bridge/wire.py", "Bridge/Device/gofly_device.py", "Bridge/Setup/setup_protocol.py",
                     "Bridge/Setup/setup_config.py", "Bridge/Setup/setup_journal.py", "Bridge/Setup/setup_producer.py",
                     "Bridge/Setup/setup_adapters.py", "Bridge/Setup/setup_support.py", "Bridge/Setup/ipa_store.py",
                     "Bridge/Setup/ipa_resign.py", "SigningStub/main.c", "SigningStub/GoFly.xcodeproj/project.pbxproj"] {
            try Data("# fixture".utf8).write(to: resources.appendingPathComponent(path))
        }
        let python = resources.appendingPathComponent("Python/python/install/bin/python3.14")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        return (resources, developer)
    }

    @Test func derivesEveryRuntimePathFromBundleResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (resources, developer) = try makeBundle(at: root)
        let bundle = try MacBundleResources(resourcesURL: resources, developerDirectoryURL: developer)

        #expect(bundle.pythonURL == resources.appendingPathComponent("Python/python/install/bin/python3.14"))
        #expect(bundle.bridgeURL == resources.appendingPathComponent("Bridge/bridge.py"))
        #expect(bundle.projectURL == resources.appendingPathComponent("SigningStub/GoFly.xcodeproj"))
        #expect(bundle.stateRootURL.path.hasSuffix("Library/Application Support/GoFly/state"))
    }

    @Test func bundleIdentifierIsDerivedFromEachSelectedTeam() throws {
        #expect(MacBundleIdentifier.forTeamID("ABCDE12345") == "com.neven.gofly.abcde12345")
        #expect(MacBundleIdentifier.forTeamID("ABCDEFGHIJ") == "com.neven.gofly.abcdefghij")
        #expect(MacBundleIdentifier.forTeamID("bad") == nil)
        #expect(!MacBundleIdentifier.isGoFly("com.neven.gofly"))
    }

    @Test func rejectsAResourceRootThatIsASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (resources, developer) = try makeBundle(at: root)
        let alias = root.appendingPathComponent("ResourcesAlias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: resources)
        #expect(throws: CheckFailure.bundleInvalid) {
            try MacBundleResources(resourcesURL: alias, developerDirectoryURL: developer)
        }
    }

    @Test func rejectsMissingSigningStub() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (resources, developer) = try makeBundle(at: root)
        try FileManager.default.removeItem(at: resources.appendingPathComponent("SigningStub/main.c"))
        #expect(throws: CheckFailure.bundleInvalid) {
            try MacBundleResources(resourcesURL: resources, developerDirectoryURL: developer)
        }
    }
}
