import XCTest

final class QuranUITests: XCTestCase {
    @MainActor private func openQuran(arabic: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor func testBrowseJumpAndTranslationSelection() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        XCTAssertTrue(app.staticTexts["quran-translation-2:1"].waitForExistence(timeout: 10))
        app.buttons["quran-jump"].tap()
        app.alerts.textFields.firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("255")
        app.alerts.buttons["Go"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].waitForExistence(timeout: 5))
        app.buttons["quran-translation-picker"].tap()
        app.buttons["None"].tap()
        XCTAssertFalse(app.staticTexts["quran-translation-2:255"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quran-translation-1:1"].exists)
    }

    @MainActor func testArabicReaderAtAccessibilitySize() {
        let app = openQuran(arabic: true, largeText: true)
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic Quran accessibility size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testSearchReferenceAndNavigateToVerse() {
        let app = openQuran()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("2:255")
        let result = app.buttons["quran-result-2:255"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].waitForExistence(timeout: 10))
    }

    @MainActor func testArabicDefaultsAndFullTextSearch() {
        let app = openQuran(arabic: true)
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quran-translation-1:1"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("الله")
        XCTAssertTrue(app.buttons["quran-result-1:1"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic Quran search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
