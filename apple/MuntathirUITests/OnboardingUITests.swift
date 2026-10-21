import XCTest

final class OnboardingUITests: XCTestCase {
    @MainActor func testLocationRequiredAndPickerAvailable() {
        let app = launch()
        app.buttons["onboarding-continue"].tap()
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        app.buttons["Choose a location"].tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use device location"].exists)
    }

    @MainActor func testBackInterruptionAndCompletion() {
        let app = launch(extra: ["--ui-testing-mecca"])
        capture("Welcome", in: app)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Mecca"].exists)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Prayer calculations"].exists)
        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(app.staticTexts["Choose your location"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-mecca" }
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Muntathir"].waitForExistence(timeout: 5))
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Mecca"].exists)
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["Enable notifications"].exists)
        app.buttons["onboarding-finish"].tap()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to Muntathir"].exists)
    }

    @MainActor func testArabicAtAccessibilitySize() {
        let app = launch(extra: ["--ui-testing-mecca", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], arabic: true)
        XCTAssertTrue(app.staticTexts["مرحبًا بك في منتظر"].waitForExistence(timeout: 5))
        capture("Arabic welcome accessibility", in: app)
        for _ in 0 ..< 3 {
            tapScrolling(app.buttons["onboarding-continue"], in: app)
        }
        tapScrolling(app.buttons["onboarding-finish"], in: app)
        XCTAssertTrue(app.buttons["اليوم"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testLocationDenialKeepsCitySearchAvailable() {
        let app = launch()
        app.buttons["onboarding-continue"].tap()
        app.buttons["Choose a location"].tap()
        let monitor = addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for title in ["Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.buttons["Use device location"].tap()
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Location access is disabled. Search for a city instead."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.searchFields["Search for a city"].exists)
        app.buttons["Use device location"].tap()
        XCTAssertTrue(app.searchFields["Search for a city"].exists)
    }

    @MainActor func testNotificationDenialAllowsCompletion() {
        let app = launch(extra: ["--ui-testing-mecca"])
        for _ in 0 ..< 3 {
            app.buttons["onboarding-continue"].tap()
        }
        let monitor = addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let deny = alert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
                return true
            }
            let alternate = alert.buttons["Don't Allow"]
            if alternate.exists {
                alternate.tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.buttons["Enable notifications"].tap()
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Notifications are disabled. Enable them in system Settings."].waitForExistence(timeout: 10))
        app.buttons["onboarding-finish"].tap()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func launch(extra: [String] = [], arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-onboarding", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
