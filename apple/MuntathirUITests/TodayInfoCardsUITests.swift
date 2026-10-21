import XCTest

final class TodayInfoCardsUITests: XCTestCase {
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
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Today date and weather squares"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Settings"].tap()
        let toggle = app.switches["Show feels-like temperature"]
        for _ in 0 ..< 6 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 100 {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        for _ in 0 ..< 8 where !app.staticTexts["Feels like"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Feels like"].exists)
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
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Arabic date and weather squares"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
