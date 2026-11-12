import XCTest

final class TasbihUITests: XCTestCase {
    @MainActor private func open(arabic: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extraArguments
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["tasbih"].tap()
        XCTAssertTrue(app.staticTexts["tasbih-count"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func pull(_ app: XCUIApplication, dx: CGFloat = 0, dy: CGFloat = 100) {
        let beads = app.descendants(matching: .any)["tasbih-beads"].firstMatch
        let start = beads.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)))
    }

    @MainActor func testPullValidationResetAndFreshVisit() {
        let app = open()
        pull(app, dy: 25)
        pull(app, dy: -80)
        pull(app, dx: 100, dy: 10)
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 34")
        pull(app, dy: 180)
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "1 / 34")
        app.buttons["tasbih-reset"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "1 / 34")
        app.buttons["tasbih-reset"].tap()
        app.alerts.buttons["Reset"].tap()
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 34")
        pull(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tasbih"].tap()
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 34")
    }

    @MainActor func testStagesCompletionAndRestart() {
        let app = open()
        for count in 1 ... 100 {
            pull(app)
            if count == 34 {
                XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الحمد لله")
                XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 33")
            } else if count == 67 {
                XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "سبحان الله")
                XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 33")
            }
        }
        XCTAssertTrue(app.descendants(matching: .any)["tasbih-complete"].firstMatch.exists)
        pull(app)
        XCTAssertEqual(app.staticTexts["tasbih-total"].label, "100 / 100")
        app.buttons["tasbih-restart"].tap()
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, "0 / 34")
    }

    @MainActor func testArabicLayout() {
        let app = open(arabic: true)
        XCTAssertTrue(app.navigationBars["تسبيح"].exists)
        XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الله أكبر")
        pull(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testLargeArabicTextAndBackgroundResume() {
        let app = open(arabic: true, extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let initial = app.staticTexts["tasbih-count"].label
        pull(app, dy: 60)
        let counted = app.staticTexts["tasbih-count"].label
        XCTAssertNotEqual(initial, counted)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(app.staticTexts["tasbih-count"].label, counted)
    }
}
