import XCTest

/// R8: dragging the map never changes the panel; a Pin collapses it to 96 pt (D3) and closing the card returns to D1.
final class GoFlyRouteCollapseUITests: GoFlyRouteModeTestCase {
    private func visibleHeight(_ app: XCUIApplication) -> CGFloat {
        Thread.sleep(forTimeInterval: 0.9)
        return element(app, "map.bottomBar").frame.minY - element(app, "map.sheet").frame.minY
    }

    func testMapDragKeepsPanelAndPinCollapsesThenCloseRestores() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        for id in ["recovery.connectionBanner.dismiss"] {
            let toast = app.buttons[id]
            if toast.waitForExistence(timeout: 2) { toast.tap() }
        }
        let full = visibleHeight(app)

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.22)))
        XCTAssertEqual(visibleHeight(app), full, accuracy: 1, "dragging the map does not change the panel")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.22)).tap()
        let card = element(app, "map.route.confirmCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(visibleHeight(app), 96, accuracy: 1, "a Pin collapses the panel to 96 pt")
        evidence(app, task: "R8", name: "pin-collapsed-light")

        element(app, "map.route.confirmCard.dismiss").tap()
        XCTAssertEqual(visibleHeight(app), full, accuracy: 1, "closing the card returns to D1")
    }
}
