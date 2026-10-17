import XCTest

final class MuntathirUITests: XCTestCase {
    @MainActor func testTodayShowsMeccaPrayerSchedule() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prayer times"].waitForExistence(timeout: 10))
        for prayer in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "prayer-" + prayer).firstMatch.exists)
        }
        XCTAssertFalse(app.staticTexts["Today’s observances"].exists)
        XCTAssertFalse(app.staticTexts["Daily ayah"].exists)
    }

    @MainActor func testPrayerSetupIsVisibleOnToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prayer times"].waitForExistence(timeout: 10))
        app.buttons["Choose a location"].firstMatch.tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use device location"].exists)
    }

    @MainActor func testEnglishNavigationAndManualCorrection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prayer times"].waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "Calendar").firstMatch.tap()
        app.buttons["Adjust this month"].tap()
        XCTAssertTrue(app.navigationBars["Adjust month"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Manual month correction"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "Qibla").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Choose a location"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Location, Not selected"].tap()
        XCTAssertTrue(app.searchFields["Search for a city"].waitForExistence(timeout: 5))
    }
    @MainActor func testArabicNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.staticTexts["أوقات الصلاة"].waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "التقويم").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["التقويم"].exists)
        app.descendants(matching: .any).matching(identifier: "القبلة").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["اختر موقعًا"].exists)
    }
}
