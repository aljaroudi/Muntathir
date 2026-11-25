import XCTest

final class TasbihUITests: XCTestCase {
    @MainActor private func open(arabic: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extraArguments
        app.launch()
        app.openTool("tasbih")
        XCTAssertTrue(stageCounter(app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func stageCounter(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["tasbih-count"]
    }

    @MainActor private func pull(_ app: XCUIApplication, dx: CGFloat = 0, dy: CGFloat = 100) {
        let beads = app.descendants(matching: .any)["tasbih-beads"].firstMatch
        let frame = beads.exists ? beads.frame : app.images["tasbih-complete"].frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)))
    }

    @MainActor func testPullValidationAndFreshVisit() {
        let app = open()
        pull(app, dy: 25)
        pull(app, dy: -80)
        pull(app, dx: 100, dy: 10)
        XCTAssertEqual(stageCounter(app).label, "0")
        pull(app, dy: 180)
        XCTAssertEqual(stageCounter(app).label, "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tasbih"].tap()
        XCTAssertEqual(stageCounter(app).label, "0")
    }

    @MainActor func testStagesCompletion() {
        // TasbihSessionTests covers every count; here we only check each boundary reaches the screen.
        let app = open(extraArguments: ["--ui-testing-tasbih-total", "33"])
        XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الله أكبر")
        pull(app)
        XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الحمد لله")
        XCTAssertEqual(stageCounter(app).label, "0")
        app.terminate()

        let finishing = open(extraArguments: ["--ui-testing-tasbih-total", "99"])
        XCTAssertEqual(finishing.staticTexts["tasbih-phrase"].label, "سبحان الله")
        pull(finishing)
        XCTAssertTrue(finishing.images["tasbih-complete"].exists)
        XCTAssertFalse(finishing.staticTexts["tasbih-phrase"].exists)
        pull(finishing)
        XCTAssertEqual(stageCounter(finishing).label, "33")
    }

    @MainActor func testSwipeHintReturnsOnEveryVisit() {
        let app = open()
        let hint = app.images["tasbih-swipe-hint"]
        XCTAssertTrue(hint.exists)
        pull(app)
        XCTAssertEqual(stageCounter(app).label, "1")
        XCTAssertFalse(hint.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tasbih"].tap()
        XCTAssertTrue(hint.exists)
        app.terminate()
        let relaunched = open(extraArguments: ["--ui-testing-preserve-state"])
        XCTAssertTrue(relaunched.images["tasbih-swipe-hint"].exists)
    }

    @MainActor func testSwipeHintTimesOutWithoutCounting() {
        let app = open()
        let hint = app.images["tasbih-swipe-hint"]
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5))
        XCTAssertEqual(stageCounter(app).label, "0")
        XCTAssertFalse(app.staticTexts["Pull a bead down to count"].exists)
    }

    @MainActor func testArabicLayout() {
        let app = open(arabic: true)
        XCTAssertEqual(stageCounter(app).label, "٠")
        XCTAssertEqual(app.staticTexts["tasbih-phrase"].label, "الله أكبر")
        pull(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testLargeArabicTextAndBackgroundResume() {
        let app = open(arabic: true, extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let beads = app.descendants(matching: .any)["tasbih-beads"].firstMatch
        let initialFrame = beads.frame
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        let initial = stageCounter(app).label
        pull(app, dy: 60)
        let counted = stageCounter(app).label
        XCTAssertNotEqual(initial, counted)
        XCTAssertEqual(beads.frame, initialFrame)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(stageCounter(app).label, counted)
    }
}
