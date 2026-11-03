import XCTest

final class ReadingAppearanceUITests: XCTestCase {
    @MainActor func testSharedSizeBookmarksAndTranslationMenuPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["hadith"].tap()
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 15))
        app.buttons["hadith-book-bukhari"].tap()
        let row = app.buttons["hadith-result-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let bookmark = app.buttons["hadith-bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Hadith reader typography"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        XCTAssertFalse(app.buttons["hadith-translation-picker"].exists)
        app.buttons["hadith-actions"].tap()
        XCTAssertTrue(app.buttons["hadith-translation-picker"].waitForExistence(timeout: 5))
        app.buttons["reading-size"].tap()
        app.buttons["reading-size-130"].tap()
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 15))
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        app.buttons["hadith-actions"].tap()
        XCTAssertTrue(app.buttons["reading-size"].label.contains("130%"))
        app.buttons["reading-size"].tap()
        app.buttons["reading-size-130"].tap()
        for _ in 0 ..< 4 {
            if app.buttons["holy-quran"].exists {
                break
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-1"].tap()
        app.buttons["quran-reading-options"].tap()
        XCTAssertTrue(app.buttons["reading-size"].label.contains("130%"))
        app.buttons["reading-size"].tap()
        app.buttons["reading-size-reset"].tap()
        app.buttons["quran-reading-options"].tap()
        XCTAssertTrue(app.buttons["reading-size"].label.contains("100%"))
    }
}
