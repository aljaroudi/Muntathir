import XCTest

final class HadithUITests: XCTestCase {
    @MainActor private func openHadith(arabic: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if arabic {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["hadith"].tap()
        if app.buttons["hadith-download"].waitForExistence(timeout: 3) {
            throw XCTSkip("Install the Hadith pack through Apple's local asset server or TestFlight before reader UI tests.")
        }
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor func testDownloadIsExplicitWhenLibraryIsMissing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["hadith"].tap()
        if app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 3) {
            throw XCTSkip("Remove the installed Hadith pack before testing the missing-library screen.")
        }
        XCTAssertTrue(app.buttons["hadith-download"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["hadith-book-bukhari"].exists)
    }

    @MainActor func testGradingShowsJudgmentWithoutTechnicalDetails() throws {
        let app = try openHadith()
        let book = app.buttons["hadith-book-abudawud"]
        for _ in 0 ..< 5 {
            if book.exists && book.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(book.isHittable)
        book.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-number"].waitForExistence(timeout: 10))
        let judgment = app.staticTexts["Hasan Sahih"]
        for _ in 0 ..< 6 {
            if judgment.exists && judgment.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(judgment.isHittable)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Hasan Sahih").count, 1)
        XCTAssertFalse(app.staticTexts["Unspecified grader"].exists)
        XCTAssertFalse(app.buttons["Original source"].exists)
        XCTAssertFalse(app.staticTexts["Coverage"].exists)
    }

    @MainActor func testBrowseJumpReadAndPage() throws {
        let app = try openHadith()
        app.buttons["hadith-book-abudawud"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let first = rows.firstMatch.identifier
        let next = app.buttons["hadith-next-page"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertNotEqual(rows.firstMatch.identifier, first)
        app.buttons["hadith-previous-page"].tap()
        XCTAssertTrue(app.buttons[first].waitForExistence(timeout: 10))
        app.buttons["hadith-jump"].tap()
        app.alerts.textFields.firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("1")
        app.alerts.buttons["Go"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        rows.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-english"].exists)
    }

    @MainActor func testChapterFilterAndUniqueJumpReturn() throws {
        let app = try openHadith()
        app.buttons["hadith-book-abudawud"].tap()
        let chapterFilter = app.buttons["hadith-chapter-filter"]
        XCTAssertTrue(chapterFilter.waitForExistence(timeout: 10))
        chapterFilter.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Purification")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        app.buttons["hadith-jump"].tap()
        app.alerts.textFields.firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("١")
        app.alerts.buttons["Go"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].waitForExistence(timeout: 10))
        if app.buttons["BackButton"].exists {
            app.buttons["BackButton"].tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.buttons["hadith-result-14646"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["hadith-full-arabic"].exists)
    }

    @MainActor func testSearchAndReplaceQuery() throws {
        let app = try openHadith()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("intentions")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        search.buttons.firstMatch.tap()
        search.typeText("zzzzzzzzzzzzzzzz")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: rows.firstMatch)
        waitForExpectations(timeout: 10)
        search.buttons.firstMatch.tap()
        search.typeText("الأعمال")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        rows.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].waitForExistence(timeout: 10))
    }

    @MainActor func testOrderedFallbackNoticeClearsForSingleWordSearch() throws {
        let app = try openHadith()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("intent intent")
        let notice = app.staticTexts["hadith-ordered-fallback"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        search.buttons.firstMatch.tap()
        search.typeText("intent")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: notice)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-")).firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testTranslationToggleAndLabeledDetail() throws {
        let app = try openHadith()
        app.buttons["hadith-book-abudawud"].tap()
        let row = app.buttons["hadith-result-14646"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-number"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-book"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-chapter"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-author"].exists)
        let english = app.descendants(matching: .any)["hadith-full-english"]
        if !english.exists { app.swipeUp() }
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        app.buttons["hadith-translation-picker"].tap()
        app.descendants(matching: .any)["hadith-translation-english"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: english)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-number"].waitForExistence(timeout: 5))
        XCTAssertFalse(english.exists)
        app.buttons["hadith-translation-picker"].tap()
        app.descendants(matching: .any)["hadith-translation-english"].firstMatch.tap()
        if !english.exists { app.swipeUp() }
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-narrator"].exists)
    }

    @MainActor func testArabicAtAccessibilitySize() throws {
        let app = try openHadith(arabic: true)
        app.buttons["hadith-book-bukhari"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let viewport = CGRect(x: 0, y: app.frame.height * 0.3, width: app.frame.width, height: app.frame.height * 0.4)
        for _ in 0 ..< 5 {
            if !row.frame.intersection(viewport).isEmpty { break }
            app.swipeUp()
        }
        let visible = row.frame.intersection(viewport)
        XCTAssertFalse(visible.isEmpty)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-detail-number"].waitForExistence(timeout: 10))
        let arabic = app.descendants(matching: .any)["hadith-full-arabic"]
        for _ in 0 ..< 5 {
            if arabic.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(arabic.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Arabic Hadith accessibility size"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
