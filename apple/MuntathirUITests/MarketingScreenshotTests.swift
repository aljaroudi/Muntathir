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

final class MarketingScreenshotTests: XCTestCase {
    @MainActor func testStoreScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        let labels = try marketingLabels()
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--screenshot-verse", "--marketing-heading", "--sky-date", "2026-10-23T06:00:00Z",
                                "--ui-testing-weather", "--weather-condition", "clear", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].waitForExistence(timeout: 15))
        for name in ["fajr", "dhuhr", "sunset", "maghrib"] {
            XCTAssertTrue(app.descendants(matching: .any)["prayer-\(name)"].exists)
        }
        for name in ["imsak", "sunrise", "asr", "isha", "midnight"] {
            XCTAssertFalse(app.descendants(matching: .any)["prayer-\(name)"].exists)
        }
        let verse = app.staticTexts["daily-ayah-text"]
        XCTAssertTrue(verse.waitForExistence(timeout: 5))
        XCTAssertEqual(verse.label, "إِنَّ مَعَ العُسرِ يُسرًا")
        snapshot("01-Today", timeWaitingForIdle: 2)
        app.buttons[labels[0]].firstMatch.tap()
        XCTAssertTrue(app.buttons[labels[1]].waitForExistence(timeout: 5))
        snapshot("02-Calendar", timeWaitingForIdle: 2)
        app.buttons[labels[2]].firstMatch.tap()
        app.buttons["qibla"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["qibla-compass-ready"].waitForExistence(timeout: 5))
        snapshot("04-Qibla", timeWaitingForIdle: 2)
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-translation-picker"].waitForExistence(timeout: 10))
        // Capture the offline Arabic reader consistently, independent of downloaded packs.
        app.buttons["quran-translation-picker"].tap()
        app.buttons[labels[3]].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("112")
        XCTAssertTrue(app.buttons["quran-surah-112"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-112"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-112:1"].waitForExistence(timeout: 10))
        snapshot("03-Quran", timeWaitingForIdle: 2)
    }
}

final class QuranScreenshotRefreshTests: XCTestCase {
    @MainActor func testQuranScreenshot() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--screenshot-verse",
                                "--ui-testing-weather", "--sky-date", "2026-10-23T06:00:00Z", "-AppleInterfaceStyle", "Light"]
        app.launch()
        let tools = try app.buttons[marketingLabels()[2]].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-translation-picker"].waitForExistence(timeout: 10))
        app.buttons["quran-translation-picker"].tap()
        app.buttons["quran-translation-none"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("112")
        XCTAssertTrue(app.buttons["quran-surah-112"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-112"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-112:1"].waitForExistence(timeout: 10))
        snapshot("03-Quran", timeWaitingForIdle: 2)
    }
}
