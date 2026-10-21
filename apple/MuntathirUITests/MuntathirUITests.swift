import XCTest

final class MuntathirUITests: XCTestCase {
    @MainActor func testToolsPrayerCounterExplainsUnavailableSensor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let entry = app.buttons["Prayer counter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable {
            app.swipeUp()
        }
        entry.tap()
        XCTAssertTrue(app.navigationBars["Prayer counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cover the sensor during sujood"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label == %@",
            "Place your iPhone face-up, with the sensor at the top of the screen directly beneath your face during sujood. Your face must cover the sensor."
        )).firstMatch.exists)
        let unavailable = app.staticTexts["Proximity sensing is unavailable on this device."]
        for _ in 0 ..< 4 where !unavailable.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(app.buttons["Start counting"].isEnabled)
        app.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        verifyPrayerVisibility(in: app)
    }

    @MainActor func testToolsDeviceAvailability() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Qibla"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Prayer counter"].exists, UIDevice.current.userInterfaceIdiom == .phone)
        XCTAssertFalse(app.tabBars.buttons["Qibla"].exists)
        XCTAssertFalse(app.tabBars.buttons["Prayer counter"].exists)
    }

    @MainActor func testStartMenuSelectionAndExitRestoreNavigation() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-counter-sensor", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["Prayer counter"].tap()
        XCTAssertTrue(app.staticTexts["Uncovered"].waitForExistence(timeout: 5))
        capture("Counter placement", in: app)
        let start = app.buttons["Start counting"]
        for _ in 0 ..< 4 where !start.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(start.isEnabled)
        start.tap()
        for prayer in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
            XCTAssertTrue(app.buttons[prayer].waitForExistence(timeout: 3))
        }
        capture("Prayer menu", in: app)
        app.navigationBars["Prayer counter"].tap()
        XCTAssertFalse(app.buttons["Exit counter"].exists)
        XCTAssertTrue(start.isHittable)
        start.tap()
        app.buttons["Maghrib"].tap()
        XCTAssertTrue(app.staticTexts["Rakaa 1 of 3"].waitForExistence(timeout: 5))
        capture("Counting Maghrib", in: app)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertFalse(app.navigationBars["Prayer counter"].isHittable)
        app.buttons["Exit counter"].tap()
        XCTAssertTrue(app.navigationBars["Prayer counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Tools"].firstMatch.isHittable)
        XCTAssertTrue(start.isEnabled)
        app.navigationBars.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Qibla"].waitForExistence(timeout: 5))
    }

    @MainActor func testCounterAtAccessibilityTextSize() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["Prayer counter"].tap()
        XCTAssertTrue(app.staticTexts["Cover the sensor during sujood"].waitForExistence(timeout: 5))
        let start = app.buttons["Start counting"]
        for _ in 0 ..< 10 where !start.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(start.isHittable)
        XCTAssertFalse(start.isEnabled)
        capture("Counter accessibility size", in: app)
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
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.buttons["عداد الركعات"].tap()
            XCTAssertTrue(app.staticTexts["غطِّ المستشعر أثناء السجود"].waitForExistence(timeout: 5))
            capture("Counter placement Arabic", in: app)
        }
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
