import XCTest

final class RakaatTrackerUITests: XCTestCase {
    @MainActor private func open(_ argument: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let arabic = extraArguments.contains("(ar)")
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture", argument] + (arabic ? [] : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]) + extraArguments
        app.launch()
        app.openTool("rakaat-tracker")
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func choose(_ target: Int, in app: XCUIApplication) {
        app.chooseRakaat(target)
    }

    @MainActor func testDhuhrOffersAsrWithoutRecalibrating() {
        let app = open("--rakaat-demo")
        app.buttons["rakaat-prayer-dhuhr"].tap()
        let next = app.buttons["rakaat-next-prayer"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertEqual(next.label, "Start Asr")
        XCTAssertTrue(app.buttons["rakaat-complete"].exists)
        next.tap()
        XCTAssertFalse(app.staticTexts["Keep the camera uncovered in steady light while it calibrates."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["rakaat-complete"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "4 rakaat")
        XCTAssertFalse(app.buttons["rakaat-next-prayer"].exists)
    }

    @MainActor func testSelectionPreparationAndCompletion() {
        let app = open("--rakaat-demo")
        for prayer in ["fajr", "dhuhr", "asr", "maghrib", "isha"] {
            XCTAssertTrue(app.buttons["rakaat-prayer-\(prayer)"].exists)
        }
        choose(3, in: app)
        XCTAssertFalse(app.staticTexts["Starting in 5…"].exists)
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].exists)
        XCTAssertTrue(app.staticTexts["rakaat-count"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "1 rakaat")
        XCTAssertTrue(app.descendants(matching: .any)["rakaat-complete"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "3 rakaat")
        app.buttons["rakaat-complete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tasbih-beads"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-complete"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["rakaat-count"].label, "3 rakaat")
        XCTAssertFalse(app.buttons["End"].exists)
        XCTAssertFalse(app.buttons["New session"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 2))
    }

    @MainActor func testArabicCompletionPushesTasbihWithLargeText() {
        let app = open("--rakaat-demo", extraArguments: ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        choose(2, in: app)
        let start = app.buttons["rakaat-complete"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "ابدأ التسبيح")
        XCTAssertTrue(start.isHittable)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tasbih-beads"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 3))
    }

    @MainActor func testBackDuringPreparationReturnsToSelection() {
        let app = open("--rakaat-demo")
        choose(4, in: app)
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["rakaat-prayer-screen"].exists)
    }

    @MainActor func testSwipeBackReturnsToSelection() {
        let app = open("--rakaat-demo")
        choose(2, in: app)
        XCTAssertTrue(app.otherElements["rakaat-prayer-screen"].waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 3))
    }

    @MainActor func testQiblaGuidanceBeforeSelection() {
        let app = open("--rakaat-demo", extraArguments: ["--qibla-ready", "--qibla-heading"])
        XCTAssertTrue(app.staticTexts["Tilt right"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rakaat-other"].exists)
        XCTAssertFalse(app.staticTexts["Turn the phone’s top edge toward Qibla"].exists)
    }

    @MainActor func testDarknessExplainsFailureAndAllowsRetry() {
        let app = open("--rakaat-dark")
        choose(2, in: app)
        XCTAssertTrue(app.staticTexts["Too dark to count reliably"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Camera unavailable"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 3))
    }

    @MainActor func testCameraPermissionDenied() {
        let app = open("--rakaat-denied")
        choose(2, in: app)
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 3))
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
            XCTAssertTrue(app.buttons["rakaat-other"].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Prayer rug placement — " + name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}

extension XCUIApplication {
    /// Picks a rakaat count from the Other menu. Menu items lose their identifiers on iOS 27,
    /// so this also matches the item's title: the count in the app's locale.
    @MainActor func chooseRakaat(_ target: Int) {
        buttons["rakaat-other"].tap()
        let locale = Locale(identifier: launchArguments.contains("(ar)") ? "ar_SA" : "en_US")
        let item = buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS %@",
                                                "rakaat-target-\(target)", target.formatted(.number.locale(locale)))).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
    }
}
