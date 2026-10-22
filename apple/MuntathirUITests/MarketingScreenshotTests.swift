import XCTest

final class MarketingScreenshotTests: XCTestCase {
    @MainActor func testStoreScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        let locale = Locale(identifier: Snapshot.deviceLanguage.isEmpty ? "en-US" : Snapshot.deviceLanguage)
        let language = try XCTUnwrap(locale.language.languageCode?.identifier)
            + (locale.language.languageCode?.identifier == "zh" ? "-\(locale.language.script!.identifier)" : "")
        let labels = try XCTUnwrap([
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
        app.launchArguments += ["--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--sky-date", "2026-10-21T06:00:00Z",
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
        XCTAssertEqual(verse.label, "وَمَآ أَنَا۠ بِطَارِدِ ٱلْمُؤْمِنِينَ")
        snapshot("01-Today", timeWaitingForIdle: 2)
        app.buttons[labels[0]].firstMatch.tap()
        XCTAssertTrue(app.buttons[labels[1]].waitForExistence(timeout: 5))
        snapshot("03-Calendar", timeWaitingForIdle: 2)
        app.buttons[labels[2]].firstMatch.tap()
        snapshot("04-Tools", timeWaitingForIdle: 2)
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
        snapshot("02-Quran", timeWaitingForIdle: 2)
    }
}
