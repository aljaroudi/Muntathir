import XCTest

final class MarketingScreenshotTests: XCTestCase {
    @MainActor func testStoreScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        let arabic = Snapshot.deviceLanguage.hasPrefix("ar")
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
        app.buttons[arabic ? "التقويم" : "Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons[arabic ? "الشهر التالي" : "Next month"].waitForExistence(timeout: 5))
        snapshot("03-Calendar", timeWaitingForIdle: 2)
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        snapshot("04-Tools", timeWaitingForIdle: 2)
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-translation-picker"].waitForExistence(timeout: 10))
        // Capture the offline Arabic reader consistently, independent of downloaded packs.
        app.buttons["quran-translation-picker"].tap()
        app.buttons[arabic ? "بدون ترجمة" : "None"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("112")
        XCTAssertTrue(app.buttons["quran-surah-112"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-112"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quran-verse-112:1"].waitForExistence(timeout: 10))
        snapshot("02-Quran", timeWaitingForIdle: 2)
    }
}
