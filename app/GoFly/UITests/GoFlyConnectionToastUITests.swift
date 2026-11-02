import XCTest

/// A lost connection names its cause (here LocalDevVPN, the third in fix order)
/// with the shared 連線 button; the GPS-not-allowed warning toast is gone.
final class GoFlyConnectionToastUITests: GoFlyRouteModeTestCase {
    func testConnectionLostToastIsAnErrorWithAConnectButton() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let toast = element(app, "recovery.connectionBanner")
            XCTAssertEqual(element(app, "recovery.notice").label, "LocalDevVPN 未連線")
            XCTAssertEqual(element(app, "recovery.connectionBanner.message").label, "請開啟 LocalDevVPN 並連線。")
            let action = element(app, "recovery.connectionBanner.vpn")
            XCTAssertEqual(action.label, "連線", "two-character toast button")
            XCTAssertTrue((60...96).contains(toast.frame.height), "short message keeps the toast compact, got \(toast.frame.height)")
            XCTAssertFalse(app.descendants(matching: .any)["map.locationNotice"].exists, "no GPS-not-allowed toast")
            evidence(app, task: "T", name: "connection-lost-\(appearance)")
            app.terminate()
        }
    }

    func testNoGPSWarningToastInJoystickEither() throws {
        let app = launch()
        app.selectGoFlyMode("joystick")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.descendants(matching: .any)["map.locationNotice"].exists)
    }
}
