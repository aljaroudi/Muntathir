import XCTest

@MainActor private func marketingLabels() throws -> [String] {
    let locale = Locale(identifier: Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage)
    let language = try XCTUnwrap(locale.language.languageCode?.identifier)
        + (locale.language.languageCode?.identifier == "zh" ? "-\(locale.language.script!.identifier)" : "")
    return try XCTUnwrap([
        "en": ["Calendar", "Next month", "Tools", "None", "Highlight"],
        "ar": ["التقويم", "الشهر التالي", "الأدوات", "بدون ترجمة", "تظليل"],
        "fa": ["تقویم", "ماه بعد", "ابزارها", "هیچ‌کدام", "برجسته‌سازی"],
        "fr": ["Calendrier", "Mois suivant", "Outils", "Aucune", "Surligner"],
        "de": ["Kalender", "Nächster Monat", "Werkzeuge", "Keine", "Markieren"],
        "id": ["Kalender", "Bulan berikutnya", "Alat", "Tidak ada", "Sorot"],
        "it": ["Calendario", "Mese successivo", "Strumenti", "Nessuna", "Evidenzia"],
        "ja": ["カレンダー", "次の月", "ツール", "なし", "ハイライト"],
        "ms": ["Kalendar", "Bulan seterusnya", "Alatan", "Tiada", "Serlahkan"],
        "ru": ["Календарь", "Следующий месяц", "Инструменты", "Нет", "Выделить"],
        "es": ["Calendario", "Mes siguiente", "Herramientas", "Ninguna", "Resaltar"],
        "tr": ["Takvim", "Sonraki ay", "Araçlar", "Yok", "Vurgula"],
        "ur": ["تقویم", "اگلا مہینہ", "اوزار", "کوئی نہیں", "نمایاں کریں"],
        "zh-Hans": ["日历", "下个月", "工具", "无", "高亮"],
        "zh-Hant": ["行事曆", "下個月", "工具", "無", "螢光標記"],
    ][language], "Unsupported capture language: \(Snapshot.deviceLanguage)")
}

@MainActor private func selectMarketingTranslation(in app: XCUIApplication) throws {
    let locale = Locale(identifier: Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage)
    let language = locale.language.languageCode?.identifier ?? "en"
    let translationLanguage = switch language {
    case "de", "ru", "es", "fa": language
    case "zh": locale.language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
    default: "en"
    }
    let label = language == "ar" ? try marketingLabels()[3] : try XCTUnwrap(locale.localizedString(forIdentifier: translationLanguage))
    app.buttons["quran-reading-options"].tap()
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
        app.buttons[labels[0]].firstMatch.tap()
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
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["qibla"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["qibla-map-ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["qibla-heading-indicator"].waitForExistence(timeout: 5))
        snapshot("10-Qibla", timeWaitingForIdle: 2)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons[labels[2]].firstMatch.waitForExistence(timeout: 15))
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-reading-options"].waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let result = app.buttons["quran-result-94:6"]
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
        XCTAssertTrue(app.buttons[labels[2]].firstMatch.waitForExistence(timeout: 15))
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["hadith"].tap()
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
            XCTAssertTrue(app.buttons[labels[2]].firstMatch.waitForExistence(timeout: 15))
            app.buttons[labels[2]].firstMatch.tap()
            let tool = app.buttons[id]
            for _ in 0 ..< 6 where !tool.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(tool.isHittable)
            tool.tap()
        }
        openTool("supplications")
        XCTAssertTrue(app.buttons["supplication-1"].waitForExistence(timeout: 15))
        snapshot("05-Supplications", timeWaitingForIdle: 2)
        openTool("tasbih")
        XCTAssertTrue(app.staticTexts["tasbih-count"].waitForExistence(timeout: 5))
        snapshot("06-Tasbih", timeWaitingForIdle: 2)
        openTool("rakaat-tracker")
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 5))
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
        // With a sidebar there's no Tools tab.
        let tools = try app.buttons[marketingLabels()[2]].firstMatch
        let quran = app.buttons["holy-quran"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 15) || quran.exists)
        if tools.exists {
            tools.tap()
        }
        quran.tap()
        XCTAssertTrue(app.buttons["quran-reading-options"].waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let result = app.buttons["quran-result-94:6"]
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
