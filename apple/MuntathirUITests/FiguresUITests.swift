import XCTest

final class FiguresUITests: XCTestCase {
    @MainActor func testArabicAccessibilityTreeRecenters() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try launchWithFigures(app)
        app.buttons["الأدوات"].firstMatch.tap()
        app.buttons["figures"].tap()
        let prophet = app.buttons["figure-prophet-muhammad"]
        XCTAssertTrue(prophet.waitForExistence(timeout: 10))
        prophet.tap()
        app.buttons["figure-family-tree"].tap()
        let father = app.buttons["family-node-abdullah-ibn-abd-al-muttalib"]
        XCTAssertTrue(father.waitForExistence(timeout: 10))
        father.tap()
        let reset = app.buttons["العودة إلى الشخصية الأولى"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertTrue(father.waitForExistence(timeout: 5))
    }

    @MainActor func testCalendarProfileAndMarriagePicker() throws {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 1448, month: 3, day: 10, hour: 12)))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", date.ISO8601Format(),
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        try launchWithFigures(app)
        app.buttons["Calendar"].firstMatch.tap()
        let jump = app.buttons["calendar-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        jump.tap()
        app.buttons["calendar-day-1448-3-10"].tap()
        let marriage = app.buttons["observance-prophet-khadija-marriage"]
        XCTAssertTrue(marriage.waitForExistence(timeout: 5))
        marriage.tap()
        let prophet = app.buttons["figure-prophet-muhammad"]
        let khadija = app.buttons["figure-khadija-bint-khuwaylid"]
        XCTAssertTrue(prophet.waitForExistence(timeout: 5))
        XCTAssertTrue(khadija.exists)
        prophet.tap()
        XCTAssertTrue(app.buttons["figure-family-tree"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        jump.tap()
        app.buttons["calendar-day-1448-3-17"].tap()
        app.buttons["observance-prophet-birth"].tap()
        XCTAssertTrue(app.buttons["figure-family-tree"].waitForExistence(timeout: 5))
    }

    private func launchWithFigures(_ app: XCUIApplication) throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "figures", withExtension: "json"))
        app.launchEnvironment["UITEST_FIGURES"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
    }
}
