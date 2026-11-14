import XCTest

final class RulingsUITests: XCTestCase {
    @MainActor func testDefaultAuthorityAndOfflineReader() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture", "--ui-testing-rulings-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-rulings.authority", "sistani"]
        app.launch()
        let tools = app.buttons["Tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        app.buttons["rulings"].tap()
        XCTAssertTrue(app.buttons["rulings-authority"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["rulings-authority"].label.contains("Sistani"))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Prayer")
        let result = app.buttons["rulings-question-42"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.staticTexts["Original answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reading-size"].exists)
    }
}
