import XCTest

final class TodaySkyUITests: XCTestCase {
    @MainActor func testNightSkyKeepsPrayersAndSettingsUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-21T21:00:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].waitForExistence(timeout: 10))
        app.openSettingsFromTools()
        XCTAssertFalse(app.switches["Follow device tilt"].exists)
        app.leaveSettings()
        let share = app.buttons["share-daily-ayah"]
        for _ in 0 ..< 5 where !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(share.isHittable)
    }

    @MainActor func testArabicSkyKeepsPrayerLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-21T06:00:00Z",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Today sky — Arabic morning"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
