import XCTest

final class MuntathirUITests: XCTestCase {
    @MainActor func testPrayerVisibilitySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        verifyPrayerVisibility(in: app)
    }

    @MainActor func testNotificationCustomization() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap(); return true
            }
            return false
        }
        app.launch()
        app.buttons["Settings"].tap()
        let link = app.buttons["Notifications"]
        for _ in 0 ..< 4 where !link.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.switches["Time Sensitive"].waitForExistence(timeout: 5))
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
        }
        let sensitive = app.switches["Time Sensitive"]
        sensitive.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(NSPredicate(format: "value == %@", "0").evaluate(with: sensitive))
        XCTAssertTrue(app.buttons["System notification settings"].exists)
        XCTAssertTrue(app.buttons["Preview sound"].firstMatch.exists)
        XCTAssertTrue(app.switches["Fajr"].exists)
        for _ in 0 ..< 8 where !app.buttons["Import adhan recording"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Import adhan recording"].isHittable)
        app.buttons["Import adhan recording"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5) || app.buttons["Cancel"].exists)
    }

    @MainActor func testToolsDeviceAvailability() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Qibla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Prayer counter"].exists)
        XCTAssertFalse(app.tabBars.buttons["Qibla"].exists)
        XCTAssertFalse(app.tabBars.buttons["Prayer counter"].exists)
    }

    @MainActor func testQiblaWithoutHeadingBlocksArrowGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["Qibla"].tap()
        XCTAssertTrue(app.staticTexts["Compass unavailable"].waitForExistence(timeout: 5))
        capture("Blocked compass", in: app)
        XCTAssertFalse(app.staticTexts["Keep your device flat and follow the arrow."].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "from true north")).firstMatch.exists)
    }

    @MainActor private func verifyPrayerVisibility(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let link = app.buttons["Visibility"]
        for _ in 0 ..< 4 where !link.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["Visibility"].waitForExistence(timeout: 5))
        for name in ["Fajr", "Dhuhr", "Maghrib"] {
            let toggle = app.switches[name]
            XCTAssertTrue(toggle.exists)
            XCTAssertFalse(toggle.isEnabled)
            XCTAssertEqual(toggle.value as? String, "1")
        }
        XCTAssertTrue(app.switches["Imsak"].exists)
        XCTAssertTrue(app.switches["Asr"].isEnabled)
    }

    @MainActor func testLaunchWithBackgroundRefreshSchedulingEnabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-background-refresh",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        for _ in 0 ..< 2 {
            app.launch()
            XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

    @MainActor func testTodayShowsMeccaPrayerSchedule() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
        for prayer in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-" + prayer).firstMatch.exists)
        }
        XCTAssertFalse(app.staticTexts["Today’s observances"].exists)
    }

    @MainActor func testPrayerSetupIsVisibleOnToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Choose a location"].firstMatch.tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use device location"].exists)
    }

    @MainActor func testEnglishNavigationAndManualCorrection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "Calendar").firstMatch.tap()
        app.buttons["Adjust this month"].tap()
        XCTAssertTrue(app.navigationBars["Adjust month"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["Qibla"].tap()
        XCTAssertTrue(app.staticTexts["Choose a location"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Location, Not selected"].tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
    }

    @MainActor func testArabicNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.buttons["اليوم"].firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "التقويم").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["التقويم"].exists)
        app.buttons["الأدوات"].firstMatch.tap()
        app.buttons["القبلة"].tap()
        XCTAssertTrue(app.staticTexts["اختر موقعًا"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["الأدوات"].tap()
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
