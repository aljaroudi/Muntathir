import XCTest

final class TodayInfoCardsUITests: XCTestCase {
    @MainActor func testWideHomeColumnsAndSettings() throws {
        let app = XCUIApplication()
        defer { XCUIDevice.shared.orientation = .portrait }
        for language in ["en", "ar"] {
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather",
                                   "-AppleLanguages", "(\(language))"]
            app.launch()
            try XCTSkipIf(app.frame.width < 700, "Run on a regular-width display to verify two columns.")
            let prayers = app.descendants(matching: .any)["prayer-fajr"].firstMatch
            let ayah = app.staticTexts["daily-ayah-text"]
            XCTAssertTrue(prayers.waitForExistence(timeout: 10))
            XCTAssertTrue(ayah.waitForExistence(timeout: 10))
            XCTAssertTrue(prayers.isHittable)
            XCTAssertTrue(ayah.isHittable)
            if language == "ar" {
                XCTAssertLessThan(ayah.frame.maxX, prayers.frame.minX)
            } else {
                XCTAssertLessThan(prayers.frame.maxX, ayah.frame.minX)
            }
            if language == "en" {
                app.buttons["Settings"].tap()
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
                app.buttons["Done"].tap()
                XCTAssertTrue(app.buttons["share-daily-ayah"].isHittable)
            }
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor func testCardsAndFeelsLikeSetting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather", "--sky-date", "2026-10-21T21:30:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        let card = app.descendants(matching: .any)["gregorian-date-card"]
        for _ in 0 ..< 8 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(app.staticTexts["22"].exists)
        XCTAssertTrue(app.otherElements["weather-card"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["weather-attribution"].firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Today date and weather squares"
        capture.lifetime = .keepAlways
        add(capture)
        let temperature = app.staticTexts["weather-temperature"]
        let originalTemperature = temperature.label
        app.buttons["Settings"].tap()
        let toggle = app.switches["Show feels-like temperature"]
        for _ in 0 ..< 6 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 100 {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        for _ in 0 ..< 8 where !temperature.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(temperature.isHittable)
        XCTAssertNotEqual(temperature.label, originalTemperature)
        XCTAssertFalse(app.staticTexts["Feels like"].exists)
    }

    @MainActor func testWeatherScenes() {
        let app = XCUIApplication()
        for (condition, date) in [("clear", "2026-10-21T09:00:00Z"), ("clear", "2026-10-21T21:30:00Z"),
                                  ("cloudy", "2026-10-21T09:00:00Z"), ("rain", "2026-10-21T09:00:00Z"),
                                  ("snow", "2026-10-21T21:30:00Z"), ("foggy", "2026-10-21T09:00:00Z")]
        {
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather", "--weather-condition", condition,
                                   "--sky-date", date, "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
            app.launch()
            let card = app.otherElements["weather-card"]
            for _ in 0 ..< 8 where !card.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(card.isHittable)
            XCTAssertTrue(app.staticTexts["weather-temperature"].exists)
            XCTAssertFalse(app.staticTexts["Feels like"].exists)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Weather \(condition) \(date)"
            capture.lifetime = .keepAlways
            add(capture)
            app.terminate()
        }
    }

    @MainActor func testAccessibilityCardsFitScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let card = app.otherElements["weather-card"]
        for _ in 0 ..< 18 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX)
        XCTAssertTrue(app.descendants(matching: .any)["weather-attribution"].firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Accessibility weather card"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor func testLandscapeCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try XCTSkipIf(app.frame.width <= app.frame.height, "Landscape is supported on iPad only.")
        let card = app.otherElements["weather-card"]
        for _ in 0 ..< 12 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Landscape cards"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor func testArabicCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-weather",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        let card = app.descendants(matching: .any)["gregorian-date-card"]
        for _ in 0 ..< 8 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(app.otherElements["weather-card"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["weather-attribution"].firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Arabic date and weather squares"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
