import XCTest

final class SemanticSearchUITests: XCTestCase {
    @MainActor private func openReader(_ identifier: String, arabic: Bool = false, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-semantic-fixture", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture", "--ui-testing-rulings-fixture",
                               "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if dark {
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        if arabic {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if identifier == "figures", let url = Bundle(for: Self.self).url(forResource: "figures", withExtension: "json") {
            app.launchEnvironment["UITEST_FIGURES"] = (try? Data(contentsOf: url))?.base64EncodedString()
        }
        app.launch()
        app.openTool(identifier)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: identifier == "hadith" ? 30 : 10))
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

    @MainActor func testSubmittedSearchReturnsOneRowPerVerse() {
        let app = openReader("holy-quran")
        query("كرسيه", in: app)
        let local = app.buttons["quran-result-2:255"]
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "quran-result-2:255").count, 1)
    }

    @MainActor func testLiteralUnderlinesInBothQuranReadingModes() {
        let app = openReader("holy-quran", dark: true)
        query("كرسيه", in: app)
        let result = app.buttons["quran-result-2:255"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Search underline preview"
        preview.lifetime = .keepAlways
        add(preview)
        result.tap()
        for mode in ["Verses", "Mushaf"] {
            app.buttons["quran-reading-options"].tap()
            app.buttons[mode].tap()
            let target = mode == "Verses" ? "quran-verse-2:255" : "quran-page-42"
            XCTAssertTrue(app.descendants(matching: .any)[target].firstMatch.waitForExistence(timeout: 10))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Search underline " + mode
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor func testLocalReferenceDoesNotOfferOnlineSearch() {
        let app = openReader("holy-quran")
        query("2:255", in: app)
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search-by-meaning"].exists)
        XCTAssertFalse(app.tabBars.buttons["Search"].exists)
    }

    @MainActor func testSubmittedMeaningSearchOpensVerse() {
        let app = openReader("holy-quran")
        query("zzmeaningquery", in: app)
        let result = app.buttons["quran-result-2:255"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].waitForExistence(timeout: 10))
    }

    @MainActor func testChapterMeaningSearchStaysInScope() {
        let app = openReader("holy-quran")
        app.buttons["quran-surah-1"].tap()
        query("zzmeaningquery", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["local-search-empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quran-result-2:255"].exists)
        app.navigationBars.buttons["Close"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["quran-surah-2"].tap()
        query("zzmeaningquery", in: app)
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        app.buttons["quran-result-2:255"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testEditingClearsPreviousResults() {
        let app = openReader("holy-quran")
        query("zzmeaningquery", in: app)
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons["Clear text"].tap()
        field.tap()
        field.typeText("zzanotherquery")
        XCTAssertFalse(app.buttons["quran-result-2:255"].exists)
    }

    @MainActor func testHadithFallbackOpensLocalNarration() {
        let app = openReader("hadith")
        query("zzmeaningquery", in: app)
        let result = app.buttons["hadith-result-105"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].waitForExistence(timeout: 10))
    }

    @MainActor func testProviderFailureAndQueryChangeKeepLocalSearchUsable() {
        let app = openReader("holy-quran")
        query("unavailable", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["local-search-empty"].firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
    }

    @MainActor func testRankedFigureOpensProfile() {
        let app = openReader("figures")
        query("zzmeaningquery", in: app)
        let row = app.buttons["figure-prophet-muhammad"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-prophet-muhammad"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testRankedSupplicationOpensReader() {
        let app = openReader("supplications")
        query("zzmeaningquery", in: app)
        let row = app.buttons["supplication-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hadith-full-arabic"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testRankedRulingOpensAnswer() {
        let app = openReader("rulings")
        query("zzmeaningquery", in: app)
        let row = app.buttons["rulings-question-42"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textViews["Original answer"].waitForExistence(timeout: 5))
    }
}
