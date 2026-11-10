import XCTest

final class SemanticSearchUITests: XCTestCase {
    @MainActor private func openReader(_ identifier: String, arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-semantic-fixture", "--ui-testing-hadith-fixture",
                               "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if arabic {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let tools = app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        app.buttons[identifier].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func query(_ text: String, in app: XCUIApplication) {
        if !app.searchFields.firstMatch.isHittable {
            app.buttons["Search"].firstMatch.tap()
        }
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText(text + "\n")
    }

    @MainActor func testLocalReferenceDoesNotOfferOnlineSearch() {
        let app = openReader("holy-quran")
        query("2:255", in: app)
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search-by-meaning"].exists)
        XCTAssertFalse(app.tabBars.buttons["Search"].exists)
    }

    @MainActor func testEmptyLocalSearchRequiresConsentThenOpensVerse() {
        let app = openReader("holy-quran")
        query("zzmeaningquery", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quran-result-2:255"].exists)
        optIn.tap()
        let result = app.buttons["quran-result-2:255"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].waitForExistence(timeout: 10))
    }

    @MainActor func testChapterMeaningSearchStaysInScope() {
        let app = openReader("holy-quran")
        app.buttons["quran-surah-1"].tap()
        query("zzmeaningquery", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        optIn.tap()
        XCTAssertTrue(app.descendants(matching: .any)["local-search-empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quran-result-2:255"].exists)
        app.navigationBars.buttons["Close"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["quran-surah-2"].tap()
        query("zzmeaningquery", in: app)
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        optIn.tap()
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        app.buttons["quran-result-2:255"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testChangingQueryRequiresConsentAgain() {
        let app = openReader("holy-quran")
        query("zzmeaningquery", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertTrue(optIn.isHittable)
        optIn.tap()
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons["Clear text"].tap()
        field.tap()
        field.typeText("zzanotherquery\n")
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quran-result-2:255"].exists)
    }

    @MainActor func testHadithFallbackOpensLocalNarration() {
        let app = openReader("hadith")
        query("zzmeaningquery", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertTrue(optIn.isHittable)
        optIn.tap()
        let result = app.buttons["hadith-result-105"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].waitForExistence(timeout: 10))
    }

    @MainActor func testProviderFailureAndQueryChangeKeepLocalSearchUsable() {
        let app = openReader("holy-quran")
        query("unavailable", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertTrue(optIn.isHittable)
        optIn.tap()
        XCTAssertTrue(app.staticTexts["Search unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons["Clear text"].tap()
        field.tap()
        field.typeText("2:255\n")
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Search unavailable"].exists)
    }

    @MainActor func testArabicFallbackAtAccessibilitySize() {
        let app = openReader("holy-quran", arabic: true)
        query("zzmeaningquery", in: app)
        let optIn = app.buttons["search-by-meaning"]
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertTrue(optIn.isHittable)
        optIn.tap()
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
    }
}
