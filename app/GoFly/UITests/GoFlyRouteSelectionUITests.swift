import XCTest

/// R3 selected-field model and R6.1: rows only select, D5 and the map Pin fill the selected field.
final class GoFlyRouteSelectionUITests: GoFlyRouteModeTestCase {
    private let coordinate = "25.047800, 121.517000"

    func testEnteringRouteDoesNotOpenSearchAndStartIsSelected() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        XCTAssertTrue(element(app, "route.node.start").isSelected, "start is the default selected field")
        XCTAssertFalse(element(app, "route.node.destination").isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["search.panel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        evidence(app, task: "R3", name: "start-selected-light")
    }

    func testRowTapOnlySelectsAndSearchBarOpensD5ForTheSelectedField() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        element(app, "route.node.destination").tap()
        XCTAssertTrue(element(app, "route.node.destination").isSelected)
        XCTAssertFalse(element(app, "route.node.start").isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["search.panel"].exists, "a row tap never opens D5")

        app.buttons["map.searchBar"].tap()
        let chip = element(app, "search.role")
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正在選：終點"].exists, "chip names the selected field")
        XCTAssertTrue(app.buttons["search.favorites"].exists, "D5 keeps the favorites shortcut")
        evidence(app, task: "R3", name: "d5-selecting-destination-light")

        app.buttons["search.back"].tap()
        XCTAssertEqual(element(app, "route.node.destination").value as? String, "選擇目的地", "back changes nothing")
        XCTAssertEqual(element(app, "route.node.start").value as? String, "目前位置")
    }

    func testSearchResultFillsOnlyTheSelectedField() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        element(app, "route.node.destination").tap()
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText(coordinate)
        let result = app.buttons["search.result.\(coordinate)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertEqual(element(app, "route.node.destination").value as? String, coordinate)
        XCTAssertEqual(element(app, "route.node.start").value as? String, "目前位置", "start is untouched")
        XCTAssertFalse(app.descendants(matching: .any)["search.panel"].exists, "confirming returns to D1")
    }

    func testMapPinShowsConfirmNotAddAndFillsTheSelectedField() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        element(app, "route.node.destination").tap()
        // The simulator has no connection, so a toast covers the map; dismiss it first.
        for id in ["recovery.connectionBanner.dismiss"] {
            let toast = app.buttons[id]
            if toast.waitForExistence(timeout: 2) { toast.tap() }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.22)).tap()
        let confirm = element(app, "map.route.confirmCard.primaryAction")
        XCTAssertEqual(confirm.label, "確認")
        XCTAssertFalse(app.buttons["新增"].exists, "D1b add is gone")
        XCTAssertFalse(app.descendants(matching: .any)["map.route.addCard"].exists)
        evidence(app, task: "R3", name: "d4-pin-confirm-light")
        confirm.tap()
        XCTAssertNotEqual(element(app, "route.node.destination").value as? String, "選擇目的地")
        XCTAssertEqual(element(app, "route.node.start").value as? String, "目前位置")
    }
}
