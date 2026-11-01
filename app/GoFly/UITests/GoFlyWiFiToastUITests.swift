import XCTest

/// B10: with Wi-Fi missing, only the connection-lost toast shows; the separate Wi-Fi toast never stacks with it.
final class GoFlyWiFiToastUITests: GoFlyRouteModeTestCase {
    func testWiFiLossShowsOnlyTheConnectionLostToast() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-wifi-disconnected"], appearance: appearance)
            let toast = element(app, "recovery.connectionBanner")
            let pill = element(app, "map.statusPill")
            XCTAssertTrue(element(app, "recovery.notice").label.contains("連線無法使用"))
            XCTAssertEqual(element(app, "recovery.connectionBanner.message").label, "請確認 Wi-Fi 與 VPN 後重試。")
            XCTAssertFalse(app.descendants(matching: .any)["map.wifiError"].exists, "no second Wi-Fi toast")
            XCTAssertEqual(toast.frame.minY - pill.frame.maxY, 8, accuracy: 1.5, "toast sits 8 pt below the status pill")
            XCTAssertEqual(toast.frame.width, app.frame.width - 32, accuracy: 1)
            evidence(app, task: "B10", name: "wifi-toast-\(appearance)")
            app.terminate()
        }
    }
}
