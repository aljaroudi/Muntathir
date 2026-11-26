import XCTest

final class MuntathirUITests: XCTestCase {
    @MainActor func testPrayerVisibilitySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        verifyPrayerVisibility(in: app)
    }

    @MainActor func testNotificationCustomization() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap(); return true
            }
            return false
        }
        app.launch()
        app.openSettingsFromTools()
        let link = app.buttons["Notifications"]
        for _ in 0 ..< 4 where !link.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
        }
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        let sensitive = app.descendants(matching: .any).matching(identifier: "Time Sensitive").firstMatch
        XCTAssertTrue(sensitive.waitForExistence(timeout: 5))
        sensitive.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(NSPredicate(format: "value == %@", "0").evaluate(with: sensitive))
        XCTAssertTrue(app.buttons["System notification settings"].exists)
        XCTAssertTrue(app.buttons["Preview sound"].firstMatch.exists)
        XCTAssertTrue(app.switches["Fajr"].exists)
        XCTAssertFalse(app.buttons["Import adhan recording"].exists)
    }

    @MainActor func testToolsDeviceAvailability() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.usesTabSidebar {
            app.showTabSidebar()
        } else {
            app.buttons["Tools"].firstMatch.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["Qibla"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["Prayer counter"].firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Qibla"].exists)
        XCTAssertFalse(app.tabBars.buttons["Prayer counter"].exists)
    }

    @MainActor func testQiblaSavedCityDoesNotEnableMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.openTool("qibla")
        XCTAssertTrue(app.staticTexts["Precise location required"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["qibla-map-ready"].exists)
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    @MainActor func testQiblaMapWithoutHeading() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--qibla-ready", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.openTool("qibla")
        XCTAssertTrue(app.descendants(matching: .any)["qibla-map-ready"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Precise location required"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["qibla-heading-indicator"].exists)
        XCTAssertTrue(app.staticTexts["Compass unavailable"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["qibla-aligned"].exists)
        capture("Qibla map", in: app)
    }

    @MainActor func testQiblaMapWithHeading() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--qibla-ready", "--qibla-heading", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        app.openTool("qibla")
        XCTAssertTrue(app.descendants(matching: .any)["qibla-map-ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["qibla-heading-indicator"].exists)
        capture("Qibla map with heading", in: app)
    }

    @MainActor func testQiblaAligned() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--qibla-ready", "--qibla-heading", "--qibla-aligned", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.openTool("qibla")
        XCTAssertTrue(app.staticTexts["Aligned with Kaaba"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Turn left"].exists)
        XCTAssertFalse(app.staticTexts["Turn right"].exists)
        let map = app.descendants(matching: .any)["qibla-map-ready"]
        XCTAssertGreaterThan(map.frame.height, app.frame.height * 0.85)
        capture("Qibla aligned", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["Aligned with Kaaba"].waitForExistence(timeout: 5))
        capture("Qibla aligned landscape", in: app)
        XCTAssertFalse(app.buttons["settings"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSettingsFromTools()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.closeSettings()
        app.openTool("qibla")
        XCTAssertTrue(app.staticTexts["Aligned with Kaaba"].waitForExistence(timeout: 5))
    }

    @MainActor private func verifyPrayerVisibility(in app: XCUIApplication) {
        app.openSettingsPage("settings-prayers")
        XCTAssertTrue(app.navigationBars["Prayer times"].waitForExistence(timeout: 5))
        let last = app.switches["Maghrib"]
        for _ in 0 ..< 4 where !last.isHittable {
            app.swipeUp()
        }
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

    @MainActor func testSettingsLocationOpensCityPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.openSettingsFromTools()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let location = app.buttons["Location, Not selected"]
        for _ in 0 ..< 6 where !location.isHittable {
            app.swipeUp()
        }
        location.tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension MuntathirUITests {
    @MainActor func testPrayerContextMenuPreservesRequiredVisibility() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let fajr = app.descendants(matching: .any)["prayer-fajr"].firstMatch
        XCTAssertTrue(fajr.waitForExistence(timeout: 10))
        fajr.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Mute"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Hide"].exists)
        app.buttons["Mute"].tap()
        let asr = app.descendants(matching: .any)["prayer-asr"].firstMatch
        asr.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Alert"].waitForExistence(timeout: 5))
        app.buttons["Hide"].tap()
        XCTAssertFalse(asr.exists)
        XCTAssertTrue(fajr.exists)
    }
}
