import XCTest

final class RakaatTrackerUITests: XCTestCase {
    @MainActor private func open(_ argument: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let arabic = extraArguments.contains("(ar)")
        app.launchArguments = ["--ui-testing", argument] + (arabic ? [] : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]) + extraArguments
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        XCTAssertTrue(app.buttons["rakaat-tracker"].waitForExistence(timeout: 5))
        app.buttons["rakaat-tracker"].tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testSelectionPreparationAndCompletion() {
        let app = open("--rakaat-demo")
        for target in 2 ... 4 {
            XCTAssertTrue(app.buttons["rakaat-target-\(target)"].exists)
        }
        app.buttons["rakaat-target-3"].tap()
        XCTAssertFalse(app.staticTexts["Starting in 5…"].exists)
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].exists)
        XCTAssertTrue(app.staticTexts["rakaat-count"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "1 rakaat")
        XCTAssertTrue(app.navigationBars["Rakaat Tracker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["rakaat-complete"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "3 rakaat")
        XCTAssertFalse(app.buttons["End"].exists)
        XCTAssertFalse(app.buttons["New session"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 2))
    }

    @MainActor func testBackDuringPreparationReturnsToSelection() {
        let app = open("--rakaat-demo")
        app.buttons["rakaat-target-4"].tap()
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["rakaat-prayer-screen"].exists)
    }

    @MainActor func testSwipeBackReturnsToSelection() {
        let app = open("--rakaat-demo")
        app.buttons["rakaat-target-2"].tap()
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 3))
    }

    @MainActor func testQiblaGuidanceBeforeSelection() {
        let app = open("--rakaat-demo", extraArguments: ["--qibla-ready", "--qibla-heading"])
        XCTAssertTrue(app.staticTexts["Tilt right"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rakaat-target-2"].exists)
        XCTAssertFalse(app.staticTexts["Turn the phone’s top edge toward Qibla"].exists)
    }

    @MainActor func testDarknessExplainsFailureAndAllowsRetry() {
        let app = open("--rakaat-dark")
        app.buttons["rakaat-target-2"].tap()
        XCTAssertTrue(app.staticTexts["Too dark to count reliably"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Camera unavailable"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 3))
    }

    @MainActor func testCameraPermissionDenied() {
        let app = open("--rakaat-denied")
        app.buttons["rakaat-target-2"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["rakaat-complete"].exists)
    }
}

extension RakaatTrackerUITests {
    @MainActor func testPlacementDiagramLayouts() {
        for (name, arguments) in [
            ("System appearance", []),
            ("Arabic", ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]),
            ("Large text", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
        ] {
            let app = open("--rakaat-demo", extraArguments: arguments)
            XCTAssertTrue(app.buttons["rakaat-target-2"].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Prayer rug placement — " + name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
