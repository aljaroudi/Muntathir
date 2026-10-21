import XCTest

final class TodaySkyUITests: XCTestCase {
    @MainActor func testSkyPhasesKeepPrayersAndSettingsUsable() {
        let app = XCUIApplication()
        for (phase, date) in [
            ("Dawn", "2026-10-21T02:15:00Z"),
            ("Sunrise", "2026-10-21T03:19:00Z"),
            ("Morning", "2026-10-21T06:00:00Z"),
            ("Afternoon", "2026-10-21T12:00:00Z"),
            ("Noon", "2026-10-21T09:05:00Z"),
            ("Sunset", "2026-10-21T14:52:00Z"),
            ("Twilight", "2026-10-21T15:25:00Z"),
            ("Moonlit evening", "2026-10-21T16:00:00Z"),
            ("Full moon", "2024-04-23T23:49:00Z"),
            ("Night", "2026-10-21T21:00:00Z"),
        ] {
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", date,
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].waitForExistence(timeout: 10))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Today sky — \(phase)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if phase == "Night" {
                app.buttons["Settings"].tap()
                XCTAssertFalse(app.switches["Follow device tilt"].exists)
                app.buttons["Done"].tap()
                let share = app.buttons["share-daily-ayah"]
                for _ in 0 ..< 5 where !share.isHittable {
                    app.swipeUp()
                }
                XCTAssertTrue(share.isHittable)
            }
            app.terminate()
        }
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
