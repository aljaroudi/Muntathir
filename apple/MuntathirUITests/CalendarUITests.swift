import XCTest

final class CalendarUITests: XCTestCase {
    @MainActor func testOnlyTodayIsSelectedAndMonthTitleReturnsToToday() throws {
        for language in ["en", "ar"] {
            var calendar = Calendar(identifier: .islamicUmmAlQura)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
            let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 1448, month: 9, day: 21, hour: 12)))
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", today.ISO8601Format(),
                                   "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_SA" : "en_US"]
            app.launch()
            let calendarTitle = language == "ar" ? "التقويم" : "Calendar"
            app.descendants(matching: .any).matching(identifier: calendarTitle).firstMatch.tap()
            let title = app.buttons["calendar-month-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let currentMonth = title.label
            let todayButton = app.buttons["calendar-day-21"]
            XCTAssertTrue(todayButton.isSelected)
            let eventDay = app.buttons["calendar-day-1"]
            eventDay.tap()
            XCTAssertFalse(eventDay.isSelected)
            XCTAssertTrue(todayButton.isSelected)
            todayButton.tap()
            eventDay.tap()
            XCTAssertTrue(app.buttons[language == "ar" ? "بداية شهر رمضان" : "Beginning of Ramadan"].isHittable)
            let emptyDay = app.buttons["calendar-day-2"]
            emptyDay.tap()
            XCTAssertFalse(emptyDay.isSelected)
            XCTAssertTrue(todayButton.isSelected)
            XCTAssertFalse(app.descendants(matching: .any)["calendar-events-2"].exists)
            XCTAssertFalse(app.staticTexts["No observances today"].exists)
            XCTAssertFalse(app.staticTexts["لا مناسبات اليوم"].exists)
            let previous = language == "ar" ? "الشهر السابق" : "Previous month"
            app.buttons[previous].tap()
            XCTAssertNotEqual(title.label, currentMonth)
            XCTAssertFalse(app.buttons["calendar-day-21"].isSelected)
            title.tap()
            XCTAssertEqual(title.label, currentMonth)
            XCTAssertTrue(app.buttons["calendar-day-21"].isSelected)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Calendar \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
