import XCTest

final class QuranUITests: XCTestCase {
    @MainActor private func openQuran(arabic: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-quranTranslationSelection", "auto", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func search(_ text: String, in app: XCUIApplication) {
        if !app.searchFields.firstMatch.waitForExistence(timeout: 5) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if field.buttons["Clear text"].exists {
            field.buttons["Clear text"].tap()
        }
        field.typeText(text + "\n")
        if text == "255" {
            XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testSearchRowOpensVerseAndKeepsActionsSeparate() {
        let app = openQuran()
        search("2:26", in: app)
        let row = app.buttons["quran-result-2:26"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Read verse"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reading-time"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quran search row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["verse-actions-2:26"].tap()
        XCTAssertTrue(app.buttons["Copy text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quran-verse-2:26"].exists)
        app.buttons["Copy text"].tap()
        app.alerts.buttons["OK"].tap()
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:26"].waitForExistence(timeout: 10))
    }

    @MainActor func testArabicSearchReferenceIncludesChapterName() {
        let app = openQuran(arabic: true)
        search("2:26", in: app)
        let row = app.buttons["quran-result-2:26"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("البقرة"))
        XCTAssertTrue(row.label.contains("2:26"))
        XCTAssertFalse(app.descendants(matching: .any)["reading-time"].exists)
        XCTAssertTrue(app.buttons["verse-actions-2:26"].label.contains("البقرة"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic Quran search row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testChapterSearchInBothReadingModes() {
        for mode in ["Verses", "Mushaf"] {
            let app = openQuran()
            XCTAssertTrue(app.descendants(matching: .any)["reading-time"].firstMatch.exists)
            app.buttons["quran-surah-2"].tap()
            app.buttons["quran-reading-options"].tap()
            app.buttons[mode].tap()
            search("255", in: app)
            XCTAssertFalse(app.buttons["quran-jump"].exists)
            app.buttons["quran-result-2:255"].tap()
            let destination = mode == "Verses" ? "quran-verse-2:255" : "quran-page-42"
            XCTAssertTrue(app.descendants(matching: .any)[destination].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.descendants(matching: .any)["reading-time"].firstMatch.exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
            search("1:1", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["local-search-empty"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["quran-result-1:1"].exists)
            search("287", in: app)
            XCTAssertTrue(app.staticTexts["Invalid verse reference"].waitForExistence(timeout: 5))
            app.searchFields.firstMatch.tap()
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "close", "cancel")).firstMatch.tap()
            let original = mode == "Verses" ? "quran-verse-2:1" : "quran-page-2"
            XCTAssertTrue(app.descendants(matching: .any)[original].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testMushafKeyboardDoesNotResizePageOrReopenAfterClose() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        let page = app.descendants(matching: .any)["quran-page-2"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quran-verse-2:1"].waitForExistence(timeout: 10))
        let height = page.frame.height
        if !app.searchFields.firstMatch.waitForExistence(timeout: 5) {
            let button = app.buttons["Search"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        let field = app.searchFields.firstMatch
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.height, height, accuracy: 2)
        field.typeText("255")
        app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "close", "cancel")).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let reopened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.keyboards.firstMatch)
        reopened.isInverted = true
        wait(for: [reopened], timeout: 2)
        XCTAssertTrue(page.exists)
    }

    @MainActor func testMushafPagingSettlesAfterRepeatedSwipes() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        let page = { (number: Int) in app.descendants(matching: .any)["quran-page-\(number)"].firstMatch }
        func settled(_ number: Int) -> Bool {
            let predicate = NSPredicate { _, _ in
                let target = page(number)
                return target.exists && abs(target.frame.midX - app.frame.midX) < 4
            }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5)
            if result != .completed {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTFail("Page \(number) did not center. \(app.debugDescription)")
                return false
            }
            return true
        }
        guard settled(2) else { return }
        var number = 2
        for _ in 0 ..< 2 {
            for destination in Array(3 ... 7) + Array((2 ... 6).reversed()) {
                if destination > number {
                    app.swipeRight(velocity: .fast)
                } else {
                    app.swipeLeft(velocity: .fast)
                }
                guard settled(destination) else { return }
                number = destination
            }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Mushaf after repeated paging"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testMushafSearchUsesVisibleChapter() {
        let app = openQuran()
        app.buttons["quran-surah-1"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        let firstPage = app.descendants(matching: .any)["quran-page-1"].firstMatch
        XCTAssertTrue(firstPage.waitForExistence(timeout: 5))
        XCTAssertEqual(firstPage.frame.midX, app.frame.midX, accuracy: 4)
        firstPage.swipeRight()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-2"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["quran-page-2"].firstMatch.frame.midX, app.frame.midX, accuracy: 4)
        search("255", in: app)
        XCTAssertTrue(app.buttons["quran-result-2:255"].exists)
        app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "close", "cancel")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-2"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testChapterTextSearchTracksTranslationSelection() {
        for mode in ["Verses", "Mushaf"] {
            let app = openQuran()
            app.buttons["quran-surah-1"].tap()
            app.buttons["quran-reading-options"].tap()
            app.buttons[mode].tap()
            search("merciful", in: app)
            XCTAssertTrue(app.buttons["quran-result-1:1"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["quran-result-2:1"].exists)
            app.buttons["quran-result-1:1"].tap()
            app.buttons["quran-reading-options"].tap()
            app.buttons["quran-translation-picker"].tap()
            app.buttons["None"].tap()
            app.navigationBars.buttons["BackButton"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["local-search-empty"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["quran-result-1:1"].exists)
            app.terminate()
        }
    }

    @MainActor func testReadingModesPreserveVerse() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        search("255", in: app)
        app.buttons["quran-result-2:255"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-42"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["quran-page-42"].firstMatch.frame.midX, app.frame.midX, accuracy: 4)
        app.buttons["quran-verse-2:255"].firstMatch.tap()
        app.buttons["quran-verse-2:255"].firstMatch.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy text"].waitForExistence(timeout: 5))
        app.buttons["Copy text"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["Verses"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-42"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["quran-page-42"].firstMatch.frame.midX, app.frame.midX, accuracy: 4)
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-1"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testBrowseSearchAndTranslationSelection() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["quran-translation-2:1"].firstMatch.exists)
        search("255", in: app)
        app.buttons["quran-result-2:255"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-2:255"].waitForExistence(timeout: 5))
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["None"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["quran-translation-2:255"].firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["quran-result-2:255"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "close", "cancel")).firstMatch.tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quran-translation-1:1"].firstMatch.exists)
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

    @MainActor func testBundledEnglishAndNone() {
        let app = openQuran()
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 10))
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["quran-translation-1:1"].firstMatch.exists)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["None"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["quran-translation-1:1"].firstMatch.exists)
    }

    @MainActor func testMissingTranslationOffersExplicitDownload() {
        let app = openQuran()
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 10))
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["Spanish"].tap()
        XCTAssertTrue(app.buttons["quran-download"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quran translation download"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["quran-translation-1:1"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].exists)
    }

    @MainActor func testReadingBackgroundPersistsAcrossModes() {
        let app = openQuran()
        app.buttons["quran-surah-2"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["reading-background"].tap()
        app.buttons["Soft Gray"].tap()
        app.buttons["quran-reading-options"].tap()
        app.buttons["Mushaf"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-page-2"].waitForExistence(timeout: 10))
        app.buttons["quran-reading-options"].tap()
        XCTAssertTrue(app.buttons["reading-background"].exists)
        XCTAssertTrue(app.buttons["quran-translation-picker"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit highlight")).firstMatch.exists)
    }

    @MainActor func testSettingsOffersDownloadManagement() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["settings"].firstMatch.tap()
        app.buttons["settings-downloads"].tap()
        XCTAssertTrue(app.buttons["downloads-actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["downloads-remove-hadith"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["downloads-bundled-ar"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["downloads-bundled-en"].firstMatch.exists)
        XCTAssertTrue(app.buttons["downloads-get-de.bubenheim"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Downloads settings"
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
        XCTAssertFalse(app.descendants(matching: .any)["quran-translation-1:1"].firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("الله")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quran-result-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic Quran search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

extension QuranUITests {
    @MainActor func testSurahHeadingsInBothDirectionsAndJapanese() {
        for (language, tools, largeText) in [
            ("en", "Tools", false),
            ("ar", "الأدوات", false),
            ("fa", "ابزارها", false),
            ("ja", "ツール", false),
            ("ar", "الأدوات", true),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            app.buttons[tools].firstMatch.tap()
            app.buttons["holy-quran"].tap()
            let first = app.buttons["quran-surah-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 10), language)
            XCTAssertTrue(first.label.contains(language == "ar" ? "الفاتحة" : "Al-Faatiha"), language)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Quran headings \(language)\(largeText ? " large text" : "")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            first.tap()
            XCTAssertTrue(app.descendants(matching: .any)["quran-verse-1:1"].waitForExistence(timeout: 5), language)
            app.terminate()
        }
    }
}
