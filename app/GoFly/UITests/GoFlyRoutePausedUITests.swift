import XCTest

/// R7 / D10 copy and the 76 pt resume panel (gallery; a route cannot run in the simulator).
final class GoFlyRoutePausedUITests: GoFlyRouteModeTestCase {
    private func scrollTo(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let target = app.descendants(matching: .any)[id]
        for _ in 0..<14 where !target.exists || !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5), "missing \(id)")
        return target
    }

    func testPausedToastAndResumePanelMatchD10() throws {
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let panel = scrollTo(app, "gallery.resumePanel")
            XCTAssertEqual(element(app, "gallery.pausedToast.title").label.hasSuffix("路線模擬已暫停"), true)
            XCTAssertEqual(element(app, "gallery.pausedToast.message").label, "任務意外中斷，點選重試自中斷點恢復行進。")
            XCTAssertEqual(element(app, "gallery.pausedToast.action").label, "重試")
            XCTAssertEqual(panel.frame.height, 76, accuracy: 1, "narrow resume panel")
            XCTAssertEqual(element(app, "gallery.resumePanel.title").label, "路線已暫停 · 45%")
            XCTAssertEqual(element(app, "gallery.resumePanel.subtitle").label, "剩餘 1.2 km · 預估 14 分鐘")
            XCTAssertEqual(element(app, "gallery.resumePanel.action").label, "繼續")
            evidence(app, task: "R7", name: "d10-paused-\(appearance)")
            app.terminate()
        }
    }
}
