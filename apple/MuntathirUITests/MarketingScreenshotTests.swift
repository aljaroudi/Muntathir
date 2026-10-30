import XCTest

@MainActor private func marketingLabels() throws -> [String] {
    let locale = Locale(identifier: Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage)
    let language = try XCTUnwrap(locale.language.languageCode?.identifier)
        + (locale.language.languageCode?.identifier == "zh" ? "-\(locale.language.script!.identifier)" : "")
    return try XCTUnwrap([
        "en": ["Calendar", "Next month", "Tools", "None"],
        "ar": ["التقويم", "الشهر التالي", "الأدوات", "بدون ترجمة"],
        "fr": ["Calendrier", "Mois suivant", "Outils", "Aucune"],
        "de": ["Kalender", "Nächster Monat", "Werkzeuge", "Keine"],
        "id": ["Kalender", "Bulan berikutnya", "Alat", "Tidak ada"],
        "it": ["Calendario", "Mese successivo", "Strumenti", "Nessuna"],
        "ja": ["カレンダー", "次の月", "ツール", "なし"],
        "ms": ["Kalendar", "Bulan seterusnya", "Alatan", "Tiada"],
        "ru": ["Календарь", "Следующий месяц", "Инструменты", "Нет"],
        "es": ["Calendario", "Mes siguiente", "Herramientas", "Ninguna"],
        "tr": ["Takvim", "Sonraki ay", "Araçlar", "Yok"],
        "ur": ["تقویم", "اگلا مہینہ", "اوزار", "کوئی نہیں"],
        "zh-Hans": ["日历", "下个月", "工具", "无"],
        "zh-Hant": ["行事曆", "下個月", "工具", "無"],
    ][language], "Unsupported capture language: \(Snapshot.deviceLanguage)")
}

@MainActor private func selectMarketingTranslation(in app: XCUIApplication) throws {
    let locale = Locale(identifier: Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage)
    let language = locale.language.languageCode?.identifier ?? "en"
    let id = language == "ar" ? nil : (["de": "de.bubenheim", "ru": "ru.kuliev", "es": "es.bornez", "zh": locale.language.script?.identifier == "Hant" ? "zh.majian" : "zh.jian"][language] ?? "en.qarai")
    app.buttons["quran-translation-picker"].tap()
    app.buttons[id.map { "quran-translation-option-\($0)" } ?? "quran-translation-none"].tap()
}

final class MarketingScreenshotTests: XCTestCase {
    @MainActor func testStoreScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        let labels = try marketingLabels()
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--marketing-local-translations", "--screenshot-verse", "--marketing-heading", "--sky-date", "2026-10-23T06:00:00Z",
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
        let verse = app.staticTexts["daily-ayah-text"]
        XCTAssertTrue(verse.waitForExistence(timeout: 5))
        XCTAssertEqual(verse.label, "إِنَّ مَعَ العُسرِ يُسرًا")
        snapshot("01-Today", timeWaitingForIdle: 2)
        app.buttons[labels[0]].firstMatch.tap()
        XCTAssertTrue(app.buttons[labels[1]].waitForExistence(timeout: 5))
        // The fixed capture date is 1448-05; show Sha'ban for the store listing.
        for _ in 0 ..< 3 {
            app.buttons[labels[1]].tap()
        }
        snapshot("02-Calendar", timeWaitingForIdle: 2)
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["qibla"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["qibla-compass-ready"].waitForExistence(timeout: 5))
        snapshot("04-Qibla", timeWaitingForIdle: 2)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons[labels[2]].firstMatch.waitForExistence(timeout: 15))
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-translation-picker"].waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("94:6")
        XCTAssertTrue(app.buttons["quran-result-94:6"].waitForExistence(timeout: 10))
        app.buttons["quran-result-94:6"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-94:6"].waitForExistence(timeout: 10))
        if Locale(identifier: Snapshot.deviceLanguage).language.languageCode?.identifier != "ar" {
            XCTAssertTrue(app.staticTexts["quran-translation-94:6"].waitForExistence(timeout: 10))
        }
        snapshot("03-Quran", timeWaitingForIdle: 2)
    }
}

final class QuranScreenshotRefreshTests: XCTestCase {
    @MainActor func testQuranScreenshot() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--marketing-local-translations", "--screenshot-verse",
                                "--ui-testing-weather", "--sky-date", "2026-10-23T06:00:00Z", "-AppleInterfaceStyle", "Light"]
        app.launch()
        let tools = try app.buttons[marketingLabels()[2]].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-translation-picker"].waitForExistence(timeout: 10))
        try selectMarketingTranslation(in: app)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("94:6")
        XCTAssertTrue(app.buttons["quran-result-94:6"].waitForExistence(timeout: 10))
        app.buttons["quran-result-94:6"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-94:6"].waitForExistence(timeout: 10))
        if Locale(identifier: Snapshot.deviceLanguage).language.languageCode?.identifier != "ar" {
            XCTAssertTrue(app.staticTexts["quran-translation-94:6"].waitForExistence(timeout: 10))
        }
        snapshot("03-Quran", timeWaitingForIdle: 2)
    }
}
