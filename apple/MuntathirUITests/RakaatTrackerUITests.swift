import XCTest

final class RakaatTrackerUITests: XCTestCase {
    @MainActor private func open(_ argument: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", argument, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["rakaat-tracker"].tap()
        return app
    }

    @MainActor func testSelectionPreparationAndCompletion() {
        let app = open("--rakaat-demo")
        for target in 2 ... 4 {
            XCTAssertTrue(app.buttons["rakaat-target-\(target)"].exists)
        }
        app.buttons["rakaat-target-3"].tap()
        XCTAssertTrue(app.staticTexts["Starting in 5…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].exists)
        XCTAssertTrue(app.staticTexts["rakaat-count"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "1 rakaat")
        XCTAssertFalse(app.navigationBars["Rakaat Tracker"].exists)
        XCTAssertTrue(app.staticTexts["rakaat-complete"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "3 rakaat")
        XCTAssertFalse(app.buttons["End"].exists)
        XCTAssertFalse(app.buttons["New session"].exists)
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 2))
    }

    @MainActor func testEndDuringPreparationReturnsToSelection() {
        let app = open("--rakaat-demo")
        app.buttons["rakaat-target-4"].tap()
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].waitForExistence(timeout: 2))
        app.buttons["End"].tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["rakaat-prayer-screen"].exists)
    }

    @MainActor func testQiblaGuidanceBeforeSelection() {
        let app = open("--rakaat-demo", extraArguments: ["--qibla-ready", "--qibla-heading"])
        XCTAssertTrue(app.staticTexts["Tilt right"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rakaat-target-2"].exists)
        XCTAssertFalse(app.staticTexts["Turn the phone’s top edge toward Qibla"].exists)
    }

    @MainActor func testCameraPermissionDenied() {
        let app = open("--rakaat-denied")
        app.buttons["rakaat-target-2"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertFalse(app.staticTexts["rakaat-complete"].exists)
    }
}
