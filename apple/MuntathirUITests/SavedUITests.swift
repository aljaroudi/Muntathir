import XCTest

final class SavedUITests: XCTestCase {
    @MainActor private func launch(extra: [String] = [], arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extra
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        return app
    }

    @MainActor private func openVerse(_ app: XCUIApplication) {
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
    }

    @MainActor private func exerciseSavedBookmark(_ app: XCUIApplication, rowID: String, query: String) {
        XCTAssertTrue(app.segmentedControls["saved-kind"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No highlights yet"].exists)
        app.segmentedControls.buttons["Bookmarks"].tap()
        let row = app.buttons[rowID]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.buttons["saved-grouping"].tap()
        app.buttons["Group by Date"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("no-such-saved-passage")
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        search.buttons["Clear text"].tap()
        search.typeText(query)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        } else {
            app.buttons["Cancel"].tap()
        }
        row.swipeLeft()
        app.buttons["Remove Bookmark"].tap()
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Bookmarks"].isSelected)
    }

    @MainActor func testQuranBookmarkSearchGroupingRemovalAndRelaunch() {
        let app = launch()
        openVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["verse-bookmark"].tap()
        XCTAssertFalse(app.buttons["highlight-color-yellow"].exists)
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        openVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        XCTAssertTrue(app.buttons["Remove Bookmark"].waitForExistence(timeout: 5))
        // Close the menu without changing the bookmark.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-saved"].tap()
        exerciseSavedBookmark(app, rowID: "saved-verse-1:1", query: "1:1")
    }

    @MainActor func testBookmarkSaveFailureDoesNotChangeState() {
        let app = launch(extra: ["--ui-testing-quran-save-failure"])
        openVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["verse-bookmark"].tap()
        XCTAssertTrue(app.alerts["Unable to save bookmark"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["verse-actions-1:1"].tap()
        XCTAssertTrue(app.buttons["Bookmark"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Remove Bookmark"].exists)
    }

    @MainActor func testHadithBookmarkOpensSourceAndCanBeRemoved() {
        let app = launch()
        app.buttons["hadith"].tap()
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 15))
        app.buttons["hadith-book-bukhari"].tap()
        app.openFirstHadithChapter()
        app.buttons["hadith-result-1"].tap()
        XCTAssertTrue(app.buttons["hadith-bookmark"].waitForExistence(timeout: 10))
        app.buttons["hadith-bookmark"].tap()
        XCTAssertEqual(app.buttons["hadith-bookmark"].label, "Remove Bookmark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.buttons["hadith-library-menu"].exists {
            app.buttons["hadith-library-menu"].tap()
        }
        app.buttons["hadith-saved"].tap()
        app.segmentedControls.buttons["Bookmarks"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-hadith-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let rowID = row.identifier
        row.tap()
        XCTAssertTrue(app.buttons["hadith-bookmark"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["hadith-bookmark"].label, "Remove Bookmark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["Highlights"].tap()
        exerciseSavedBookmark(app, rowID: rowID, query: "1")
    }

    @MainActor func testSupplicationBookmarksStayInSupplications() {
        let app = launch(extra: ["--ui-testing-supplications-fixture"])
        app.buttons["supplications"].tap()
        XCTAssertTrue(app.buttons["supplication-1"].waitForExistence(timeout: 15))
        app.buttons["supplication-1"].tap()
        XCTAssertTrue(app.buttons["hadith-bookmark"].waitForExistence(timeout: 10))
        app.buttons["hadith-bookmark"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["supplication-saved"].tap()
        app.segmentedControls.buttons["Bookmarks"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-hadith-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let rowID = row.identifier
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["hadith"].tap()
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 10))
        if app.buttons["hadith-library-menu"].exists {
            app.buttons["hadith-library-menu"].tap()
        }
        app.buttons["hadith-saved"].tap()
        app.segmentedControls.buttons["Bookmarks"].tap()
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["supplications"].tap()
        XCTAssertTrue(app.buttons["supplication-saved"].waitForExistence(timeout: 10))
        app.buttons["supplication-saved"].tap()
        exerciseSavedBookmark(app, rowID: rowID, query: "تجريبي")
    }

    @MainActor func testArabicSavedSupportsAccessibilityTextSize() throws {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], arabic: true)
        openVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["verse-bookmark"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-saved"].tap()
        XCTAssertTrue(app.segmentedControls["saved-kind"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["الإشارات المرجعية"].tap()
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["saved-grouping"].isHittable)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic Saved at accessibility size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
