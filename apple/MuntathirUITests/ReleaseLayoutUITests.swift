import XCTest

final class ReleaseLayoutUITests: XCTestCase {
    @MainActor func testEnglishLayouts() {
        inspect(arabic: false)
    }

    @MainActor func testArabicAccessibilityLayouts() {
        inspect(arabic: true)
    }

    @MainActor private func inspect(arabic: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--qibla-ready", "--ui-testing-hadith-fixture", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US", "-AppleInterfaceStyle", arabic ? "Dark" : "Light"]
        if arabic {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        capture(app, "Today")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["reading-size"].waitForExistence(timeout: 5))
        capture(app, "Settings")
        app.buttons[arabic ? "تم" : "Done"].tap()
        app.buttons[arabic ? "التقويم" : "Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["calendar-year"].waitForExistence(timeout: 5))
        capture(app, "Calendar")
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        capture(app, "Tools")
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.buttons["quran-reading-options"].waitForExistence(timeout: 5))
        capture(app, "Quran")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["qibla"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["qibla-map-ready"].waitForExistence(timeout: 10))
        capture(app, "Qibla")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
