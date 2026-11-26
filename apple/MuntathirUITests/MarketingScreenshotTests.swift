import XCTest

@MainActor private func marketingLabels() throws -> [String] {
    try marketingLabels(for: Snapshot.deviceLanguage)
}

@MainActor private func selectMarketingTranslation(in app: XCUIApplication) throws {
    let label = try marketingTranslationLabel(for: Snapshot.deviceLanguage)
    app.buttons["quran-reading-options"].firstMatch.tap()
    app.buttons["quran-translation-picker"].tap()
    app.buttons[label].tap()
}

final class MarketingScreenshotTests: XCTestCase {
    @MainActor func testStoreScreenshots() throws {
        continueAfterFailure = false
        let appearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = appearance }
        let app = XCUIApplication()
        setupSnapshot(app)
        let labels = try marketingLabels()
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--marketing-local-translations", "--screenshot-verse", "--qibla-ready", "--qibla-heading", "--qibla-aligned", "--sky-date", "2026-10-23T06:00:00Z",
                                "--ui-testing-weather", "--weather-condition", "clear", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].waitForExistence(timeout: 15))
        let compact = app.launchArguments.contains("--marketing-compact")
        for name in ["fajr", "dhuhr", "maghrib"] + (compact ? [] : ["sunset"]) {
            XCTAssertTrue(app.descendants(matching: .any)["prayer-\(name)"].exists)
        }
        for name in ["imsak", "sunrise", "asr", "isha", "midnight"] + (compact ? ["sunset"] : []) {
            XCTAssertFalse(app.descendants(matching: .any)["prayer-\(name)"].exists)
        }
        let verse = app.descendants(matching: .any)["daily-ayah-text"].firstMatch
        XCTAssertTrue(verse.waitForExistence(timeout: 5))
        XCTAssertEqual(verse.value as? String ?? verse.label, "إِنَّ مَعَ العُسرِ يُسرًا")
        snapshot("01-Today", timeWaitingForIdle: 2)
        let calendar = app.buttons[labels[0]].firstMatch
        (calendar.exists ? calendar : app.cells[labels[0]].firstMatch).tap()
        XCTAssertTrue(app.buttons["calendar-jump"].waitForExistence(timeout: 5))
        // The fixed capture date is 1448-05; show Sha'ban for the store listing.
        app.buttons["calendar-jump"].tap()
        for _ in 0 ..< 3 {
            app.buttons[labels[1]].tap()
        }
        let day = app.buttons["calendar-day-1448-8-1"]
        for _ in 0 ..< 6 {
            if day.exists, day.isHittable {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(day.isHittable)
        day.tap()
        snapshot("09-Calendar", timeWaitingForIdle: 2)
        app.openTool("qibla")
        XCTAssertTrue(app.descendants(matching: .any)["qibla-map-ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["qibla-heading-indicator"].waitForExistence(timeout: 5))
        snapshot("10-Qibla", timeWaitingForIdle: 2)
        app.terminate()
        app.launch()
        app.openTool("holy-quran")
        XCTAssertTrue(app.buttons["quran-reading-options"].firstMatch.waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let result = app.descendants(matching: .any)["quran-result-94:6"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        if !result.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(result.isHittable)
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-94:6"].waitForExistence(timeout: 10))
        if Locale(identifier: Snapshot.deviceLanguage).language.languageCode?.identifier != "ar" {
            XCTAssertTrue(app.descendants(matching: .any)["quran-translation-94:6"].firstMatch.waitForExistence(timeout: 10))
        }
        snapshot("02-Quran", timeWaitingForIdle: 2)
        let arabicText = app.textViews["quran-arabic-94:6"]
        XCTAssertTrue(arabicText.waitForExistence(timeout: 5))
        arabicText.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.menuItems[labels[4]].waitForExistence(timeout: 5))
        app.menuItems[labels[4]].tap()
        XCTAssertTrue(app.buttons["highlight-color-green"].waitForExistence(timeout: 5))
        snapshot("04-Highlights", timeWaitingForIdle: 2)
        app.terminate()
        app.launch()
        app.openTool("hadith")
        XCTAssertTrue(app.buttons["hadith-saved"].waitForExistence(timeout: 15))
        let book = app.buttons["hadith-book-bukhari"]
        for _ in 0 ..< 12 where !book.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(book.isHittable)
        book.tap()
        app.openFirstHadithChapter()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-")).firstMatch.waitForExistence(timeout: 10))
        snapshot("03-Hadith", timeWaitingForIdle: 2)
        func openTool(_ id: String) {
            app.terminate()
            app.launch()
            app.openTool(id)
        }
        openTool("supplications")
        XCTAssertTrue(app.descendants(matching: .any)["supplication-1"].firstMatch.waitForExistence(timeout: 15))
        snapshot("05-Supplications", timeWaitingForIdle: 2)
        openTool("tasbih")
        XCTAssertTrue(app.staticTexts["tasbih-count"].waitForExistence(timeout: 5))
        snapshot("06-Tasbih", timeWaitingForIdle: 2)
        openTool("rakaat-tracker")
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 5))
        snapshot("07-Rakaat", timeWaitingForIdle: 2)
        app.launchArguments += ["--ui-testing-progress-fixture"]
        openTool("prayer-progress")
        XCTAssertTrue(app.descendants(matching: .any)["progress-prayer-chart"].firstMatch.waitForExistence(timeout: 5))
        snapshot("08-Activity", timeWaitingForIdle: 2)
    }
}

final class QuranScreenshotRefreshTests: XCTestCase {
    @MainActor func testQuranScreenshot() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--marketing-local-translations", "--screenshot-verse",
                                "--ui-testing-weather", "--sky-date", "2026-10-23T06:00:00Z", "-AppleInterfaceStyle", "Light"]
        app.launch()
        app.openTool("holy-quran")
        XCTAssertTrue(app.buttons["quran-reading-options"].firstMatch.waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let result = app.descendants(matching: .any)["quran-result-94:6"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        if !result.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(result.isHittable)
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-94:6"].waitForExistence(timeout: 10))
        if Locale(identifier: Snapshot.deviceLanguage).language.languageCode?.identifier != "ar" {
            XCTAssertTrue(app.descendants(matching: .any)["quran-translation-94:6"].firstMatch.waitForExistence(timeout: 10))
        }
        snapshot("02-Quran", timeWaitingForIdle: 2)
    }
}
