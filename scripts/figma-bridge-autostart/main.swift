import AppKit
import ApplicationServices

private let figmaID = "com.figma.Desktop"
private let pluginID = "figma-desktop-bridge-mcp"
private let pluginName = "Figma Desktop Bridge"

private struct BridgeInstallation {
    enum CheckError: String, Error {
        case figmaMissing = "Figma Desktop is not installed or its executable is missing."
        case settingsInvalid = "Cannot read Figma settings; Bridge registration is unverified."
        case bridgeNotImported = "Figma Desktop Bridge has not been imported into Figma."
        case pluginInvalid = "Registered Bridge manifest, worker or UI is missing or invalid."
    }

    let figma: URL
    let manifest: URL

    static func check(home: URL, applicationDirectories: [URL]) throws(CheckError) -> Self {
        struct Registration: Decodable {
            let manifestPath: String?
            let lastKnownPluginId: String?
        }
        struct Settings: Decodable { let localFileExtensions: [Registration]? }
        struct Manifest: Decodable { let id: String; let name: String; let main: String; let ui: String }

        let files = FileManager.default
        guard let figma = applicationDirectories.lazy.map({ $0.appendingPathComponent("Figma.app") })
            .first(where: { files.isExecutableFile(atPath: $0.appendingPathComponent("Contents/MacOS/Figma").path) })
        else { throw .figmaMissing }

        let settingsFile = home.appendingPathComponent("Library/Application Support/Figma/settings.json")
        let decoder = JSONDecoder()
        guard let settingsData = try? Data(contentsOf: settingsFile),
              let settings = try? decoder.decode(Settings.self, from: settingsData) else { throw .settingsInvalid }
        guard let registration = settings.localFileExtensions?.first(where: { $0.lastKnownPluginId == pluginID })
        else { throw .bridgeNotImported }
        guard let path = registration.manifestPath, path.hasPrefix("/") else { throw .pluginInvalid }
        let manifest = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: manifest),
              let plugin = try? decoder.decode(Manifest.self, from: data),
              plugin.id == pluginID, plugin.name == pluginName else { throw .pluginInvalid }
        let directory = manifest.deletingLastPathComponent()
        guard [plugin.main, plugin.ui].allSatisfy({ relative in
            guard !relative.isEmpty, !relative.hasPrefix("/"),
                  !relative.split(separator: "/").contains("..") else { return false }
            let asset = directory.appendingPathComponent(relative)
            return (try? asset.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && files.isReadableFile(atPath: asset.path)
        }) else { throw .pluginInvalid }
        return Self(figma: figma, manifest: manifest)
    }

    static func check(home: URL) throws(CheckError) -> Self {
        try check(home: home, applicationDirectories: [
            URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
        ])
    }
}

private extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    var children: [AXUIElement] { value(kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    var role: String? { value(kAXRoleAttribute) as? String }
    var title: String? { value(kAXTitleAttribute) as? String }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    func menuItem(named name: String) -> AXUIElement? {
        children.lazy.flatMap { $0.role == kAXMenuRole ? $0.children : [$0] }.first {
            $0.role == kAXMenuItemRole && $0.title == name
        }
    }
}

private struct FigmaEditor {
    private static let fileKinds = ["design", "file", "board", "slides", "deck"]

    enum Panel { case none, bridge, other }

    let fileKey: String
    private let webArea: AXUIElement

    static func current(in window: AXUIElement) -> Self? {
        var editors: [Self] = []
        var hasPrototype = false
        var homeIsSelected = false
        // Electron's native window can wrap each renderer in several unnamed AX groups.
        let complete = walk(window, maxDepth: 16) { element, role in
            guard role == "AXWebArea" else { return true }
            let value = element.value(kAXURLAttribute)
            guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) else { return false }
            if url.isFileURL, url.lastPathComponent == "shell.html" {
                homeIsSelected = selectedHome(in: element)
            }
            if let host = url.host, ["figma.com", "www.figma.com"].contains(host.lowercased()) {
                let path = url.pathComponents.dropFirst()
                hasPrototype = hasPrototype || path.first == "proto"
                if let kind = path.first, Self.fileKinds.contains(kind),
                   let key = path.dropFirst().first {
                    editors.append(Self(fileKey: key, webArea: element))
                }
            }
            // Webviews nested inside the shell or editor are never separate editor candidates.
            return false
        }
        guard complete, !hasPrototype, !homeIsSelected, editors.count == 1 else { return nil }
        return editors.first
    }

    // A partial scan must not be mistaken for an editor without a plugin.
    func panel() -> Panel? {
        var panel = Panel.none
        let complete = Self.walk(webArea, maxDepth: 10) { element, role in
            if panel == .bridge { return false }
            if role == kAXGroupRole || role == kAXHeadingRole {
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                    .compactMap { element.value($0) as? String }
                if names.contains(pluginName) || names.contains("Plugin: \(pluginName)") {
                    panel = .bridge
                    return false
                }
                if names.contains(where: { $0.hasPrefix("Plugin: ") }) {
                    panel = .other
                }
            }
            if role == "AXWebArea", !CFEqual(element, webArea) {
                let rawURL = element.value(kAXURLAttribute)
                let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:))
                if let url, ["figma.com", "www.figma.com"].contains(url.host?.lowercased() ?? ""),
                   url.path == "/plugin-sandbox" {
                    panel = .other
                }
                return false
            }
            return role == "AXWebArea" || role == kAXGroupRole
        }
        if panel != .none { return panel }
        return complete ? Panel.none : nil
    }

    private static func selectedHome(in shell: AXUIElement) -> Bool {
        var selected = false
        _ = walk(shell, maxDepth: 10) { element, role in
            if selected { return false }
            if [kAXRadioButtonRole, "AXTab"].contains(role) {
                let name = element.title ?? element.value(kAXDescriptionAttribute) as? String
                selected = name == "Home" && element.value(kAXValueAttribute) as? Int == 1
            }
            return !selected
        }
        return selected
    }

    private static func walk(
        _ root: AXUIElement, maxDepth: Int, descend: (AXUIElement, String) -> Bool
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        var level = [root]
        for depth in 0...maxDepth {
            guard level.count <= 120 else { return false }
            var next: [AXUIElement] = []
            for element in level {
                guard ProcessInfo.processInfo.systemUptime < deadline, let role = element.role else {
                    return false
                }
                if descend(element, role), depth < maxDepth {
                    next.append(contentsOf: element.children)
                }
            }
            level = next
        }
        return true
    }
}

@MainActor
private final class BridgeAutostart {
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let workspace = NSWorkspace.shared
    private var figmaPID: pid_t?
    private var accessibilityRequestedAt = -Double.infinity
    private var handledFiles: Set<String> = []
    private var pending: [String: TimeInterval] = [:]
    private var retryAfter: [String: TimeInterval] = [:]
    private var lastStatus: (String, String)?
    private var requestedPermission = false

    private var activeFigmaPID: pid_t? {
        guard let frontmost = workspace.frontmostApplication,
              frontmost.bundleIdentifier == figmaID else { return nil }
        return frontmost.processIdentifier
    }

    func tick() {
        do {
            _ = try BridgeInstallation.check(home: home)
        } catch {
            status("installation-missing", error.rawValue)
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: figmaID)
        let nextPID = activeFigmaPID ?? running.first?.processIdentifier
        if figmaPID != nextPID {
            figmaPID = nextPID
            accessibilityRequestedAt = -.infinity
            handledFiles.removeAll()
            retryAfter.removeAll()
            pending.removeAll()
        }
        guard let figmaPID else {
            status("waiting-for-figma", "Figma is not running.")
            return
        }
        guard AXIsProcessTrusted() else {
            if !requestedPermission {
                requestedPermission = true
                // kAXTrustedCheckOptionPrompt is imported as a mutable C global in Swift 6.
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            status("permission-required", "Enable Figma Bridge Autostart in System Settings > Privacy & Security > Accessibility.")
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let app = AXUIElementCreateApplication(figmaPID)
        // Electron can expose only its native window until an accessibility client requests the web tree.
        // Enable it for this Figma process only and retry if the renderer has not initialized yet.
        if now - accessibilityRequestedAt >= 5,
           accessibilityRequestedAt == -.infinity || lastStatus?.0 == "waiting-for-editor" {
            accessibilityRequestedAt = now
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        guard activeFigmaPID == figmaPID else {
            status("waiting-for-foreground", "Waiting for Figma to be in the foreground.")
            return
        }
        guard let window = app.element(kAXFocusedWindowAttribute) else {
            status("waiting-for-editor", "No focused Figma window.")
            return
        }
        guard let editor = FigmaEditor.current(in: window) else {
            status("waiting-for-editor", "Waiting for a Figma Design, FigJam or Slides editor.")
            return
        }
        let file = editor.fileKey
        guard let panel = editor.panel() else {
            status("waiting-for-editor", "Waiting for the Figma editor's accessibility tree.")
            return
        }
        if panel == .bridge {
            handledFiles.insert(file)
            pending.removeValue(forKey: file)
            retryAfter.removeValue(forKey: file)
            status("bridge-running", "The Figma Desktop Bridge panel is open.")
            return
        }
        if let deadline = pending[file] {
            if now < deadline {
                status("verifying", "Waiting for the Figma Desktop Bridge panel.")
                return
            }
            pending.removeValue(forKey: file)
            retryAfter[file] = now + 60
        }
        guard !handledFiles.contains(file) else {
            status("already-handled", "The Bridge was open in this file. A manual close is respected until Figma restarts.")
            return
        }
        guard now >= retryAfter[file, default: 0] else {
            status("retry-wait", "The Bridge did not open. Retrying after a short delay.")
            return
        }
        guard panel == .none else {
            status("waiting-for-plugin", "Another plugin is open in the Figma editor.")
            return
        }
        guard isIdle(app: app, window: window) else {
            status("waiting-for-idle", "Waiting for Figma input or its dialog to clear.")
            return
        }
        guard let plugins = app.element(kAXMenuBarAttribute)?.children.first(where: {
            $0.role == kAXMenuBarItemRole && $0.title == "Plugins"
        }) else {
            status("waiting-for-menu", "Waiting for the Plugins menu.")
            return
        }
        if launchBridge(from: plugins, in: app, window: window, file: file, pid: figmaPID) {
            pending[file] = ProcessInfo.processInfo.systemUptime + 20
            status("verifying", "Requested the registered Bridge from the Plugins menu.")
        } else {
            retryAfter[file] = now + 60
            status("retry-wait", "Could not run Plugins > Development > Figma Desktop Bridge.")
        }
    }

    private func isIdle(app: AXUIElement, window: AXUIElement) -> Bool {
        let inputRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXMenuRole, kAXMenuItemRole]
        var focused = app.element(kAXFocusedUIElementAttribute)
        for _ in 0..<8 {
            guard let element = focused, !CFEqual(element, window) else { break }
            if inputRoles.contains(element.role ?? "") { return false }
            focused = element.element(kAXParentAttribute)
        }
        let dialogs = [kAXSheetRole, kAXDialogSubrole, kAXSystemDialogSubrole]
        guard window.value(kAXModalAttribute) as? Bool != true,
              !dialogs.contains(window.value(kAXSubroleAttribute) as? String ?? ""),
              !window.children.contains(where: { dialogs.contains($0.role ?? "") }) else {
            return false
        }
        return noRecentInput()
    }

    private func noRecentInput() -> Bool {
        let input: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        return input.allSatisfy {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) > 2
        }
    }

    private func launchBridge(
        from plugins: AXUIElement, in app: AXUIElement, window: AXUIElement, file: String, pid: pid_t
    ) -> Bool {
        var openedMenu = false
        // Figma can expose hidden menu items whose AXPress reports success without running them.
        // Open each ancestor before resolving or pressing its child.
        func expand(_ parent: AXUIElement) -> Bool {
            guard activeFigmaPID == pid, noRecentInput(),
                  parent.perform(kAXPressAction) || parent.perform(kAXShowMenuAction) else { return false }
            openedMenu = true
            return true
        }
        var invoked = false
        defer {
            if openedMenu, !invoked, activeFigmaPID == pid, noRecentInput() {
                plugins.children.first(where: { $0.role == kAXMenuRole })?.perform(kAXCancelAction)
            }
        }
        guard expand(plugins), let development = plugins.menuItem(named: "Development"),
              expand(development), let plugin = development.menuItem(named: pluginName),
              activeFigmaPID == pid else { return false }

        // Figma versions may expose the plugin as a leaf or as a submenu with Run.
        let target: AXUIElement
        if plugin.children.contains(where: { $0.role == kAXMenuRole }) {
            guard expand(plugin), let run = plugin.menuItem(named: "Run") else { return false }
            target = run
        } else {
            target = plugin
        }
        guard target.value(kAXEnabledAttribute) as? Bool == true,
              let focused = app.element(kAXFocusedWindowAttribute), CFEqual(focused, window),
              FigmaEditor.current(in: focused)?.fileKey == file,
              activeFigmaPID == pid, noRecentInput() else { return false }
        invoked = target.perform(kAXPressAction)
        return invoked
    }

    private func status(_ state: String, _ reason: String) {
        guard lastStatus?.0 != state || lastStatus?.1 != reason else { return }
        let directory = home.appendingPathComponent("Library/Application Support/Figma Bridge Autostart")
        let record: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "state": state,
            "reason": reason,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
            lastStatus = (state, reason)
        } catch {
            NSLog("Cannot write Figma Bridge Autostart status: %@", error.localizedDescription)
        }
    }
}

if CommandLine.arguments.dropFirst().elementsEqual(["--check"]) {
    var result: [String: Any] = ["accessibility": AXIsProcessTrusted()]
    var returnCode: Int32 = 0
    do {
        let installation = try BridgeInstallation.check(home: FileManager.default.homeDirectoryForCurrentUser)
        result["installed"] = true
        result["figma"] = installation.figma.path
        result["manifest"] = installation.manifest.path
    } catch {
        result["installed"] = false
        result["error"] = error.rawValue
        returnCode = 1
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(returnCode)
}

guard CommandLine.arguments.count == 1 else {
    FileHandle.standardError.write(Data("Usage: FigmaBridgeAutostart [--check]\n".utf8))
    exit(2)
}
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
private let watcher = BridgeAutostart()
watcher.tick()
let timer = Timer(timeInterval: 5, repeats: true) { _ in
    MainActor.assumeIsolated { watcher.tick() }
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
