import XCTest

final class CalendarUITests: XCTestCase {
    @MainActor private func openAdjustments(_ app: XCUIApplication) {
        app.openSettingsFromTools()
        let link = app.buttons["month-adjustments"]
        for _ in 0 ..< 8 {
            if link.isHittable {
                break
            }
            app.swipeUp()
        }
        link.tap()
    }

    @MainActor func testDatePickerChangesMonthWithoutReplacingSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar-jump"].tap()
        let title = app.staticTexts["calendar-month-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let original = title.label
        let frame = app.navigationBars["Jump to date"].frame
        for _ in 0 ..< 3 {
            app.buttons["Next month"].tap()
            XCTAssertTrue(app.navigationBars["Jump to date"].exists)
            XCTAssertNotEqual(title.label, original)
            XCTAssertEqual(app.navigationBars["Jump to date"].frame, frame)
            app.buttons["Previous month"].tap()
            XCTAssertEqual(title.label, original)
        }
        app.buttons["Done"].tap()
        XCTAssertFalse(title.exists)
    }

    @MainActor func testSettingsMonthAdjustmentSaveResetAndDiscard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-23T06:00:00Z", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openAdjustments(app)
        let stepper = app.steppers["month-offset"]
        let original = stepper.label
        stepper.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["month-adjustments"].tap()
        XCTAssertEqual(stepper.label, original)
        app.buttons["Next month"].tap()
        app.buttons["Previous month"].tap()
        XCTAssertEqual(stepper.label, original)
        stepper.buttons.element(boundBy: 0).tap()
        let changed = stepper.label
        app.buttons["Save"].tap()
        app.buttons["month-adjustments"].tap()
        XCTAssertEqual(stepper.label, changed)
        app.buttons["Reset adjustment"].tap()
        app.buttons["month-adjustments"].tap()
        XCTAssertEqual(stepper.label, original)
    }

    @MainActor func testCalendarCollapseSelectionAndEventDates() throws {
        try checkCalendar(language: "en", accessibilityText: false)
    }

    @MainActor func testCalendarEventDatesAtAccessibilityTextSize() throws {
        // Arabic covers right-to-left layout and Arabic digits together with the largest text size.
        try checkCalendar(language: "ar", accessibilityText: true)
    }

    @MainActor func testYearNavigationAndExpectedDates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-23T06:00:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["calendar-jump"].waitForExistence(timeout: 5))
        XCTAssertTrue(showsYear(app, "1448"))
        openTitleMenu(app)
        app.buttons["Next year"].tap()
        XCTAssertTrue(showsYear(app, "1449"))
        let firstMonth = app.descendants(matching: .any)["calendar-month-1449-1"].firstMatch
        XCTAssertTrue(firstMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(firstMonth.isHittable)
        app.buttons["calendar-jump"].tap()
        XCTAssertTrue(app.staticTexts["Future dates are estimates until the month’s moonsighting is confirmed or the month begins."].exists)
        XCTAssertTrue(app.buttons["calendar-day-1449-1-1"].waitForExistence(timeout: 5))
        app.buttons["calendar-day-1449-1-1"].tap()
        let event = app.descendants(matching: .any)["calendar-events-1449-1-2"].firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Expected:")).firstMatch.exists)
        app.buttons["calendar-today"].tap()
        XCTAssertTrue(showsYear(app, "1448"))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-countdown"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-countdown"].firstMatch.isHittable)
        openTitleMenu(app)
        app.buttons["Previous year"].tap()
        XCTAssertTrue(showsYear(app, "1447"))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-month-1447-1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-month-1447-1"].firstMatch.isHittable)
    }

    @MainActor func testMonthMenuAndScrollBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-23T06:00:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["calendar-jump"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["Section index"].exists)
        // The system title menu exposes items by label only.
        let lastMonthItem = app.buttons["Dhuʻl-Hijjah"]
        XCTAssertFalse(lastMonthItem.exists)
        openTitleMenu(app)
        lastMonthItem.tap()
        let lastMonth = app.descendants(matching: .any)["calendar-month-1448-12"].firstMatch
        XCTAssertTrue(lastMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(lastMonth.isHittable)
        XCTAssertFalse(lastMonthItem.exists)
        // A month jump lands its header just below the navigation bar, not partway down the screen.
        openTitleMenu(app)
        app.buttons["Shawwal"].tap()
        let shawwal = app.descendants(matching: .any)["calendar-month-1448-10"].firstMatch
        XCTAssertTrue(shawwal.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertTrue(shawwal.isHittable)
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        XCTAssertEqual(shawwal.frame.minY, barBottom, accuracy: 40, "header at \(shawwal.frame.minY), bar bottom \(barBottom)")
        openTitleMenu(app)
        lastMonthItem.tap()
        // Scrolling back up by hand must reach the first month.
        let firstMonth = app.descendants(matching: .any)["calendar-month-1448-1"].firstMatch
        for _ in 0 ..< 30 where !(firstMonth.exists && firstMonth.isHittable) {
            app.swipeDown()
        }
        XCTAssertTrue(firstMonth.isHittable)
        openTitleMenu(app)
        lastMonthItem.tap()
        XCTAssertTrue(lastMonth.waitForExistence(timeout: 5))
        openTitleMenu(app)
        app.buttons["Muharram"].tap()
        XCTAssertTrue(firstMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(firstMonth.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Month menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Opens the navigation title menu that holds year switching and month jumps.
    @MainActor private func openTitleMenu(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let button = bar.buttons["Calendar"]
        (button.exists ? button : bar.staticTexts["Calendar"]).tap()
    }

    @MainActor private func showsYear(_ app: XCUIApplication, _ year: String) -> Bool {
        app.navigationBars.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "\(year) AH")).firstMatch.waitForExistence(timeout: 5)
    }

    @MainActor private func checkCalendar(language: String, accessibilityText: Bool) throws {
        continueAfterFailure = false
        let locale = Locale(identifier: language == "ar" ? "ar_SA" : "en_US")
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 1448, month: 9, day: 21, hour: 12)))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 1448, month: 9, day: 1)))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", today.ISO8601Format(),
                               "-AppleLanguages", "(\(language))", "-AppleLocale", locale.identifier]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                accessibilityText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let calendarTitle = language == "ar" ? "التقويم" : "Calendar"
        app.descendants(matching: .any).matching(identifier: calendarTitle).firstMatch.tap()
        let jump = app.buttons["calendar-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-countdown"].exists)
        XCTAssertFalse(app.buttons["calendar-day-1448-9-21"].exists)
        jump.tap()
        let title = app.staticTexts["calendar-month-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let currentMonth = title.label
        let previous = language == "ar" ? "الشهر السابق" : "Previous month"
        let next = language == "ar" ? "الشهر التالي" : "Next month"
        app.buttons[previous].tap()
        XCTAssertNotEqual(title.label, currentMonth)
        app.buttons[next].tap()
        XCTAssertEqual(title.label, currentMonth)
        let todayButton = app.buttons["calendar-day-1448-9-21"]
        if !accessibilityText {
            XCTAssertTrue(todayButton.isSelected)
        }
        app.buttons["calendar-day-1448-9-1"].tap()
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        assertEventDates(app, calendar: calendar, locale: locale, date: firstDay)

        openAdjustments(app)
        let stepper = app.steppers["month-offset"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons["month-offset-Increment"].tap()
        app.buttons[language == "ar" ? "حفظ" : "Save"].tap()
        app.leaveSettings(for: "calendar")
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.tap()
        app.buttons["calendar-day-1448-9-1"].tap()
        let correctedFirstDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: firstDay))
        assertEventDates(app, calendar: calendar, locale: locale, date: correctedFirstDay)
        XCTAssertFalse(app.descendants(matching: .any)["calendar-events-1448-9-2"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Calendar \(language)\(accessibilityText ? " large text" : "")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor private func assertEventDates(_ app: XCUIApplication, calendar: Calendar, locale: Locale, date: Date,
                                             file: StaticString = #filePath, line: UInt = #line)
    {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM"
        let row = app.otherElements["calendar-events-1448-9-1"].descendants(matching: .staticText)
        let historicalYear = locale.language.languageCode?.identifier == "ar" ? "٢٠٠ هـ" : "200 AH"
        let expectedHijri = historicalYear
        let hijri = row.matching(NSPredicate(format: "label == %@", expectedHijri)).firstMatch
        XCTAssertTrue(hijri.waitForExistence(timeout: 5), file: file, line: line)
        let hijriLabel = hijri.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(hijriLabel, expectedHijri, file: file, line: line)
        XCTAssertTrue(hijri.isHittable, file: file, line: line)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let civil = row.matching(NSPredicate(format: "label == %@", formatter.string(from: date))).firstMatch
        XCTAssertTrue(civil.waitForExistence(timeout: 3), app.otherElements["calendar-events-1448-9-1"].debugDescription, file: file, line: line)
        XCTAssertEqual(civil.label, formatter.string(from: date), file: file, line: line)
        XCTAssertTrue(civil.isHittable, file: file, line: line)
    }
}

extension CalendarUITests {
    @MainActor func testCalendarSettingsOnlyExposeManualAdjustments() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.openSettingsFromTools()
        let adjustments = app.buttons["month-adjustments"]
        for _ in 0 ..< 5 where !adjustments.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(adjustments.isHittable)
        XCTAssertFalse(app.buttons["calendar-method"].exists)
        XCTAssertFalse(app.staticTexts["Middle East"].exists)
        XCTAssertFalse(app.buttons["calendar-country"].exists)
    }
}

extension CalendarUITests {
    @MainActor func testMonthAdjustmentAtAccessibilityTextSize() {
        // German has the longest labels; Arabic large text is covered by testCalendarEventDatesAtAccessibilityTextSize.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(de)", "-AppleLocale", "de",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let tab = app.descendants(matching: .any).matching(identifier: "Kalender").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        openAdjustments(app)
        let adjustment = app.steppers["month-offset"]
        XCTAssertTrue(adjustment.waitForExistence(timeout: 5))
        let button = adjustment.buttons.element(boundBy: 0)
        for _ in 0 ..< 5 where !button.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Month adjustment large text de"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Sichern"].tap()
        XCTAssertTrue(app.buttons["month-adjustments"].waitForExistence(timeout: 5))
    }
}
