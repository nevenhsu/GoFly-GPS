import XCTest

/// B10: with Wi-Fi missing, only the Wi-Fi issue (first in fix order) shows; no second toast stacks with it.
final class GoFlyWiFiToastUITests: GoFlyRouteModeTestCase {
    func testWiFiLossShowsOnlyTheWiFiIssueToast() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-wifi-disconnected"], appearance: appearance)
            let toast = element(app, "recovery.connectionBanner")
            let pill = element(app, "map.statusPill")
            XCTAssertEqual(element(app, "recovery.notice").label, "Wi-Fi 未連線")
            XCTAssertEqual(element(app, "recovery.connectionBanner.message").label, "請將 iPhone 連上 Wi-Fi。")
            XCTAssertEqual(element(app, "recovery.connectionBanner.wifi").label, "設定")
            XCTAssertFalse(app.descendants(matching: .any)["map.wifiError"].exists, "no second Wi-Fi toast")
            XCTAssertEqual(toast.frame.minY - pill.frame.maxY, 8, accuracy: 1.5, "toast sits 8 pt below the status pill")
            XCTAssertEqual(toast.frame.width, app.frame.width - 32, accuracy: 1)
            evidence(app, task: "B10", name: "wifi-toast-\(appearance)")
            app.terminate()
        }
    }
}
