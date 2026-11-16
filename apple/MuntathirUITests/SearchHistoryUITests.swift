import XCTest

final class SearchHistoryUITests: XCTestCase {
    @MainActor private func launch(arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture",
                               "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if arabic {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    @MainActor private func openQuran(_ app: XCUIApplication, arabic: Bool = false) {
        let tools = app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor private func focus(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.isHittable {
            app.buttons["Search"].firstMatch.tap()
        }
        field.tap()
        return field
    }

    @MainActor private func clearField(_ app: XCUIApplication) {
        let field = focus(app)
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }

    @MainActor func testSubmitReuseRemoveAndClearHistory() {
        let app = launch()
        openQuran(app)
        let field = focus(app)
        if app.buttons["search-history-clear"].exists {
            app.buttons["search-history-clear"].tap()
        }
        field.typeText("2:255\n")
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        clearField(app)
        let recent = app.descendants(matching: .any)["search-history-2:255"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "2:255")
        clearField(app)
        app.buttons["search-history-remove-2:255"].tap()
        XCTAssertFalse(recent.exists)
        field.typeText("94:6\n")
        XCTAssertTrue(app.buttons["quran-result-94:6"].waitForExistence(timeout: 5))
        clearField(app)
        app.buttons["search-history-clear"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["search-history-94:6"].firstMatch.exists)
    }

    @MainActor func testOpeningResultSavesWithoutSubmitAndSurvivesRelaunch() {
        let app = launch()
        openQuran(app)
        let field = focus(app)
        if app.buttons["search-history-clear"].exists {
            app.buttons["search-history-clear"].tap()
        }
        field.typeText("2:255\n")
        let result = app.buttons["quran-result-2:255"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        openQuran(app)
        _ = focus(app)
        XCTAssertTrue(app.descendants(matching: .any)["search-history-2:255"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["search-history-clear"].tap()
    }

    @MainActor func testArabicLargeTextMatchPreview() {
        let app = launch(arabic: true)
        openQuran(app, arabic: true)
        focus(app).typeText("كرسيه\n")
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact Arabic match at accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
