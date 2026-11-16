import XCTest

final class FiguresUITests: XCTestCase {
    @MainActor func testLaqabDisclosureInEnglish() throws {
        try checkLaqabDisclosure(language: "en", locale: "en_US", tools: "Tools",
                                 more: "Show more laqabs", fewer: "Show fewer laqabs")
    }

    @MainActor func testLaqabDisclosureInArabic() throws {
        try checkLaqabDisclosure(language: "ar", locale: "ar_SA", tools: "الأدوات",
                                 more: "عرض المزيد من الألقاب", fewer: "عرض ألقاب أقل")
    }

    @MainActor private func checkLaqabDisclosure(language: String, locale: String, tools: String,
                                                 more: String, fewer: String) throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        try launchWithFigures(app)
        app.buttons[tools].firstMatch.tap()
        app.buttons["figures"].tap()
        let hasan = app.buttons["figure-hasan-ibn-ali"]
        XCTAssertTrue(hasan.waitForExistence(timeout: 10))
        hasan.tap()

        let showMore = app.buttons[more]
        let showFewer = app.buttons[fewer]
        let fourthLaqab = app.staticTexts["كَريم أهل البيت"]
        XCTAssertTrue(showMore.waitForExistence(timeout: 5))
        XCTAssertFalse(fourthLaqab.exists)
        showMore.tap()
        XCTAssertTrue(showFewer.waitForExistence(timeout: 5))
        XCTAssertTrue(fourthLaqab.exists)
        showFewer.tap()
        XCTAssertTrue(showMore.waitForExistence(timeout: 5))
        XCTAssertFalse(fourthLaqab.exists)

        showMore.tap()
        XCTAssertTrue(showFewer.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["figure-husayn-ibn-ali"].tap()
        XCTAssertTrue(showMore.waitForExistence(timeout: 5))
    }

    @MainActor func testSiblingSectionInEnglish() throws {
        try checkSiblingSection(language: "en", locale: "en_US", tools: "Tools", siblings: "Siblings")
    }

    @MainActor func testArabicSiblingSectionAtAccessibilitySize() throws {
        try checkSiblingSection(language: "ar", locale: "ar_SA", tools: "الأدوات", siblings: "الإخوة والأخوات",
                                textSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    @MainActor private func checkSiblingSection(language: String, locale: String, tools: String, siblings: String,
                                                textSize: String = "UICTContentSizeCategoryL") throws
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                               "-UIPreferredContentSizeCategoryName", textSize]
        try launchWithFigures(app)
        app.buttons[tools].firstMatch.tap()
        app.buttons["figures"].tap()
        let prophet = app.buttons["figure-prophet-muhammad"]
        XCTAssertTrue(prophet.waitForExistence(timeout: 10))
        prophet.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-prophet-muhammad"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["figure-family-tree"].exists)
        let father = app.buttons["figure-relative-abdullah-ibn-abd-al-muttalib"]
        for _ in 0 ..< 15 where !father.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(father.isHittable)
        father.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-abdullah-ibn-abd-al-muttalib"].firstMatch.waitForExistence(timeout: 5))
        let header = app.staticTexts[siblings]
        for _ in 0 ..< 10 where !header.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(header.isHittable)
        XCTAssertTrue(app.buttons["figure-relative-abu-talib"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-prophet-muhammad"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        jump.tap()
        app.buttons["calendar-day-1448-3-17"].tap()
        app.buttons["observance-prophet-birth"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-prophet-muhammad"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor private func launchWithFigures(_ app: XCUIApplication) throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "figures", withExtension: "json"))
        app.launchEnvironment["UITEST_FIGURES"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture"]
        app.launch()
    }
}
