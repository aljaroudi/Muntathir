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
        app.openFirstHadithChapter()
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
        XCTAssertFalse(app.buttons["hadith-translation-picker"].exists)
        app.buttons["hadith-actions"].tap()
        XCTAssertTrue(app.buttons["hadith-translation-picker"].waitForExistence(timeout: 5))
        app.buttons["reading-size"].tap()
        XCTAssertTrue(app.buttons["reading-size-increase"].waitForExistence(timeout: 5))
        for _ in 0 ..< 3 {
            app.buttons["reading-size-increase"].tap()
        }
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 15))
        XCTAssertEqual(bookmark.label, "Remove Bookmark")
        app.buttons["hadith-actions"].tap()
        app.buttons["reading-size"].tap()
        XCTAssertTrue(app.buttons["reading-size-increase"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["reading-size-increase"].value as? String, "130%")
        if app.otherElements["PopoverDismissRegion"].firstMatch.exists {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        } else {
            app.sheets.firstMatch.swipeDown()
        }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["reading-size-increase"])
        waitForExpectations(timeout: 5)
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
        app.buttons["reading-size"].tap()
        XCTAssertTrue(app.buttons["reading-size-increase"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["reading-size-increase"].value as? String, "130%")
        for _ in 0 ..< 3 {
            app.buttons["reading-size-increase"].tap()
        }
        XCTAssertFalse(app.buttons["reading-size-increase"].isEnabled)
        for _ in 0 ..< 8 {
            app.buttons["reading-size-decrease"].tap()
        }
        XCTAssertFalse(app.buttons["reading-size-decrease"].isEnabled)
        app.buttons["reading-size-reset"].tap()
        XCTAssertEqual(app.buttons["reading-size-increase"].value as? String, "100%")
        XCTAssertFalse(app.buttons["reading-size-reset"].isEnabled)
    }
}

extension ReadingAppearanceUITests {
    @MainActor func testContentsAndSizePanelFitViewport() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["hadith"].tap()
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 10))
        app.buttons["hadith-book-bukhari"].tap()
        let chapter = app.buttons["hadith-chapter-1"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.frame.contains(chapter.frame))
        let contents = XCTAttachment(screenshot: app.screenshot())
        contents.name = "Hadith contents layout"
        contents.lifetime = .keepAlways
        add(contents)
        chapter.tap()
        XCTAssertTrue(app.buttons["hadith-result-1"].waitForExistence(timeout: 10))
        app.buttons["hadith-result-1"].tap()
        XCTAssertTrue(app.buttons["hadith-actions"].waitForExistence(timeout: 10))
        app.buttons["hadith-actions"].tap()
        app.buttons["reading-size"].tap()
        let increase = app.buttons["reading-size-increase"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(increase.frame))
        XCTAssertTrue(app.buttons["reading-size-reset"].isHittable)
        XCTAssertTrue(app.staticTexts["Text size"].isHittable)
        increase.tap()
        XCTAssertEqual(increase.value as? String, "110%")
        let controls = XCTAttachment(screenshot: app.screenshot())
        controls.name = "Text size panel layout"
        controls.lifetime = .keepAlways
        add(controls)
    }
}
