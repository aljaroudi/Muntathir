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
        snapshot("01-Today", timeWaitingForIdle: 2)
        app.buttons[arabic ? "التقويم" : "Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons[arabic ? "الشهر التالي" : "Next month"].waitForExistence(timeout: 5))
        snapshot("03-Calendar", timeWaitingForIdle: 2)
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        snapshot("04-Tools", timeWaitingForIdle: 2)
    }
}
