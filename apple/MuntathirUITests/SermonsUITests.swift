import XCTest

final class SermonsUITests: XCTestCase {
    @MainActor func testOpenBundledSermonAndSwitchEditions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["sermons"].tap()
        app.buttons["sermon-fadak"].tap()
        let picker = app.buttons["sermon-edition"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // Attribution lives in the Settings app, not the reader.
        XCTAssertFalse(app.buttons["Source"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "روى عبد الله بن الحسن")).firstMatch.exists)
        app.swipeUp()
        let visiblePassages = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "arabic-"))
            .allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)
        XCTAssertFalse(visiblePassages.isEmpty)
        for (language, label) in [("Deutsch", "Ahl al-Bayt Weltversammlung"), ("English", "Ahl al-Bayt World Assembly"), ("English", "Literal"), ("English", "Simplified"),
                                  ("简体中文", "Literal"), ("简体中文", "Simplified")]
        {
            picker.tap()
            app.buttons[language].tap()
            app.buttons[label].tap()
            XCTAssertEqual(picker.label, language + " · " + label)
            XCTAssertTrue(visiblePassages.contains { app.staticTexts[$0].isHittable })
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["sermon-fadak"].exists)
    }

    @MainActor func testSpeakerOpensFigureProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["sermons"].tap()
        let row = app.buttons["sermon-fadak"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.staticTexts["Fatima al-Zahra"].waitForExistence(timeout: 5))
        row.tap()
        let speaker = app.buttons["sermon-speaker"]
        XCTAssertTrue(speaker.waitForExistence(timeout: 5))
        speaker.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-fatima-al-zahra"].waitForExistence(timeout: 5))
    }
}
