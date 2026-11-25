import XCTest

final class RulingsUITests: XCTestCase {
    @MainActor func testDefaultAuthorityAndOfflineReader() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture", "--ui-testing-rulings-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-rulings.authority", "sistani"]
        app.launch()
        app.openTool("rulings")
        XCTAssertTrue(app.buttons["rulings-authority"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["rulings-authority"].label.contains("Sistani"))
        XCTAssertTrue(app.descendants(matching: .any)["rulings-notice"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["rulings-language-en"].waitForExistence(timeout: 5))
        let result = app.buttons["rulings-question-42"]
        XCTAssertFalse(result.exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Prayer\n")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.textViews["Original answer"].waitForExistence(timeout: 5))
        let section = app.buttons["rulings-section-3"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()
        XCTAssertTrue(app.navigationBars["Worship"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rulings-question-43"].waitForExistence(timeout: 5))
        XCTAssertTrue(result.exists)
        XCTAssertFalse(app.buttons["rulings-question-44"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["reading-options"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["rulings-notice"].firstMatch.exists)
        let bookmark = app.buttons["ruling-bookmark"]
        XCTAssertTrue(bookmark.exists)
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove Bookmark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        }
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }
        app.buttons["rulings-saved"].tap()
        // Saved opens on highlights.
        XCTAssertTrue(app.segmentedControls["saved-kind"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Bookmarks"].tap()
        let saved = app.buttons["saved-ruling-42"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.textViews["Original answer"].waitForExistence(timeout: 5))
        app.buttons["ruling-bookmark"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 5))
    }
}
