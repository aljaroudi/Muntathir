import XCTest

final class TasbihUITests: XCTestCase {
    @MainActor private func open(arabic: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extraArguments
        app.launch()
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["tasbih"].tap()
        XCTAssertTrue(stageCounter(app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func stageCounter(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".* / .*")).firstMatch
    }

    @MainActor private func pull(_ app: XCUIApplication, dx: CGFloat = 0, dy: CGFloat = 100) {
        let beads = app.descendants(matching: .any)["tasbih-beads"].firstMatch
        let frame = beads.frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)))
    }

    @MainActor func testPullValidationResetAndFreshVisit() {
        let app = open()
        pull(app, dy: 25)
        pull(app, dy: -80)
        pull(app, dx: 100, dy: 10)
        XCTAssertEqual(stageCounter(app).label, "0 / 34")
        pull(app, dy: 180)
        XCTAssertEqual(stageCounter(app).label, "1 / 34")
        app.buttons["tasbih-reset"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(stageCounter(app).label, "1 / 34")
        app.buttons["tasbih-reset"].tap()
        app.alerts.buttons["Reset"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tasbih-total"].label, "0 / 100")
        XCTAssertTrue(stageCounter(app).wait(for: \.label, toEqual: "0 / 34", timeout: 5))
        pull(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tasbih"].tap()
        XCTAssertEqual(stageCounter(app).label, "0 / 34")
    }

    @MainActor func testStagesCompletionAndRestart() {
        let app = open()
        for count in 1 ... 100 {
            pull(app)
            if count == 34 {
                XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الحمد لله")
                XCTAssertEqual(stageCounter(app).label, "0 / 33")
            } else if count == 67 {
                XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "سبحان الله")
                XCTAssertEqual(stageCounter(app).label, "0 / 33")
            }
        }
        XCTAssertTrue(app.descendants(matching: .any)["tasbih-complete"].firstMatch.exists)
        pull(app)
        XCTAssertEqual(app.staticTexts["tasbih-total"].label, "100 / 100")
        app.buttons["tasbih-restart"].tap()
        XCTAssertEqual(stageCounter(app).label, "0 / 34")
    }

    @MainActor func testSwipeHintDismissesAfterCountingAndStaysDismissed() {
        let app = open()
        let hint = app.images["tasbih-swipe-hint"]
        XCTAssertTrue(hint.exists)
        pull(app)
        XCTAssertEqual(stageCounter(app).label, "1 / 34")
        XCTAssertFalse(hint.exists)
        app.buttons["tasbih-reset"].tap()
        app.alerts.buttons["Reset"].tap()
        XCTAssertFalse(hint.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tasbih"].tap()
        XCTAssertFalse(hint.exists)
        app.terminate()
        let relaunched = open(extraArguments: ["--ui-testing-preserve-state"])
        XCTAssertFalse(relaunched.images["tasbih-swipe-hint"].exists)
    }

    @MainActor func testSwipeHintTimesOutWithoutCounting() {
        let app = open()
        let hint = app.images["tasbih-swipe-hint"]
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5))
        XCTAssertEqual(stageCounter(app).label, "0 / 34")
        XCTAssertFalse(app.staticTexts["Pull a bead down to count"].exists)
    }

    @MainActor func testArabicLayout() {
        let app = open(arabic: true)
        XCTAssertEqual(stageCounter(app).label, "٠ / ٣٤")
        XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الله أكبر")
        pull(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testLargeArabicTextAndBackgroundResume() {
        let app = open(arabic: true, extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let initial = stageCounter(app).label
        pull(app, dy: 60)
        let counted = stageCounter(app).label
        XCTAssertNotEqual(initial, counted)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(stageCounter(app).label, counted)
    }
}
