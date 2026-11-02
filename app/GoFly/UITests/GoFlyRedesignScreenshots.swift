import XCTest

/// Visual acceptance only: the three requested rendering samples, without
/// multiplying operation states, languages, permissions, or device conditions.
@MainActor
final class GoFlyRedesignScreenshots: XCTestCase {
    func testCaptureSharedButtonComponentsLightAndDark() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Shared component gallery screenshots run on the simulator.")
        #else
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-gallery", "-gofly-ui-shared-components",
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-gofly-ui-preferences-appearance", appearance,
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            let scroll = app.scrollViews["gallery.sharedComponents"]
            wait(scroll)

            let iconButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.iconButton."))
            XCTAssertEqual(iconButtons.count, 64)
            let iconTextButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.iconTextButton."))
            XCTAssertEqual(iconTextButtons.count, 50)
            let textButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.textButton."))
            XCTAssertEqual(textButtons.count, 50)
            XCTAssertTrue(app.buttons["gallery.statusAction.danger"].exists)
            XCTAssertTrue(app.buttons["gallery.statusAction.warning"].exists)
            XCTAssertTrue(app.buttons["gallery.statusAction.success"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["gallery.field.default"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["gallery.field.focused"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["gallery.field.disabled"].exists)

            for position in 0...8 {
                if position > 0 { scroll.swipeUp() }
                Thread.sleep(forTimeInterval: 0.2)
                snapshot(app, "shared-button-components-\(appearance)-\(position)")
            }
            app.terminate()
        }
        #endif
    }

    func testSharedIconButtonsKeepFortyFourPointTargetsAtAccessibilitySize() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Shared component accessibility screenshots run on the simulator.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-gallery", "-gofly-ui-shared-components",
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-preferences-appearance", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        app.launch()
        let scroll = app.scrollViews["gallery.sharedComponents"]
        wait(scroll)
        let smallIcon = app.buttons["gallery.iconButton.standard.extraSmall.enabled"]
        XCTAssertTrue(smallIcon.waitForExistence(timeout: 10))
        XCTAssertTrue(smallIcon.isHittable)
        XCTAssertGreaterThanOrEqual(smallIcon.frame.width, 44)
        XCTAssertGreaterThanOrEqual(smallIcon.frame.height, 44)
        let smallTextButton = app.buttons["gallery.iconTextButton.primary.extraSmall.enabled"]
        XCTAssertTrue(smallTextButton.waitForExistence(timeout: 10))
        for _ in 0..<8 where !smallTextButton.isHittable { scroll.swipeUp() }
        XCTAssertTrue(smallTextButton.isHittable)
        XCTAssertGreaterThanOrEqual(smallTextButton.frame.height, 44)
        snapshot(app, "shared-button-targets-axxxl")
        app.terminate()
        #endif
    }

    func testCaptureOnboardingScreens() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual samples run on the simulator.")
        #else
        continueAfterFailure = false
        for sample in ["light", "dark", "axxxl"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly.onboarding.complete", "NO", "-gofly-ui-unreachable",
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-gofly-ui-preferences-appearance", sample == "dark" ? "dark" : "light",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if sample == "axxxl" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            wait(app.buttons["onboarding.welcome.next"])
            snapshot(app, "precision-onboarding-welcome-\(sample)")
            app.buttons["onboarding.welcome.next"].tap()
            wait(app.buttons["onboarding.location.skip"])
            snapshot(app, "precision-onboarding-location-\(sample)")
            app.buttons["onboarding.location.skip"].tap()
            wait(app.buttons["onboarding.localNetwork.allow"])
            snapshot(app, "precision-onboarding-localNetwork-\(sample)")
            app.buttons["onboarding.localNetwork.allow"].tap()
            wait(app.buttons["onboarding.vpn.check"])
            snapshot(app, "precision-onboarding-vpn-\(sample)")
            wait(app.descendants(matching: .any)["onboarding.vpn.failure"])
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
            let help = app.buttons["onboarding.vpn.help.open"]
            wait(help)
            help.tap()
            wait(app.buttons["onboarding.vpn.help.step1.action"])
            Thread.sleep(forTimeInterval: 0.45)
            snapshot(app, "precision-vpn-help-\(sample)")
            app.terminate()
        }
        #endif
    }

    func testExecutionControlsAtAccessibilitySize() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual samples run on the simulator.")
        #else
        for sample in ["light", "dark", "axxxl"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-gallery",
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-gofly-ui-preferences-appearance", sample == "dark" ? "dark" : "light",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if sample == "axxxl" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            if sample == "axxxl" {
                let shuffle = app.buttons["joystick.randomDestination"]
                for _ in 0..<10 where !shuffle.isHittable { app.swipeUp() }
                wait(shuffle)
                XCTAssertTrue(shuffle.isHittable)
                XCTAssertGreaterThanOrEqual(shuffle.frame.height, 44)
                snapshot(app, "precision-execution-destination-axxxl")
                let pause = app.buttons["execution.pause"]
                for _ in 0..<8 where !pause.isHittable { app.swipeUp() }
                wait(pause)
                XCTAssertTrue(pause.isHittable)
                XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
                snapshot(app, "precision-execution-controls-axxxl")
            }
            let pad = app.descendants(matching: .any)["joystick.pad"]
            for _ in 0..<10 where !pad.isHittable { app.swipeUp() }
            wait(pad)
            Thread.sleep(forTimeInterval: 0.3)
            snapshot(app, "step-5-joystick-pad-\(sample)")
            app.terminate()
        }
        #endif
    }

    private func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
