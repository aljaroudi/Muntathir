import XCTest

final class CalendarUITests: XCTestCase {
    @MainActor private func openAdjustments(_ app: XCUIApplication) {
        app.buttons["settings"].firstMatch.tap()
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
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        try checkCalendar(accessibilityText: false)
    }

    @MainActor func testCalendarEventDatesAtAccessibilityTextSize() throws {
        try checkCalendar(accessibilityText: true)
    }

    @MainActor func testYearNavigationAndExpectedDates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-23T06:00:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        let year = app.buttons["calendar-year"]
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        XCTAssertTrue(year.label.contains("1448"))
        app.buttons["Next year"].tap()
        XCTAssertTrue(year.label.contains("1449"))
        let firstMonth = app.buttons["calendar-month-1449-1"]
        XCTAssertTrue(firstMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(firstMonth.isHittable)
        firstMonth.tap()
        XCTAssertTrue(app.staticTexts["Future dates are estimates until the month’s moonsighting is confirmed or the month begins."].exists)
        XCTAssertTrue(app.buttons["calendar-day-1449-1-1"].waitForExistence(timeout: 5))
        app.buttons["calendar-day-1449-1-1"].tap()
        let event = app.descendants(matching: .any)["calendar-events-1449-1-2"].firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Expected:")).firstMatch.exists)
        app.buttons["calendar-today"].tap()
        XCTAssertTrue(year.label.contains("1448"))
        XCTAssertTrue(app.descendants(matching: .any)["calendar-countdown"].firstMatch.isHittable)
        app.buttons["Previous year"].tap()
        XCTAssertTrue(year.label.contains("1447"))
        XCTAssertTrue(app.buttons["calendar-month-1447-1"].isHittable)
    }

    @MainActor func testMonthMenuAndStickyHeader() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--sky-date", "2026-10-23T06:00:00Z",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["calendar-year"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["Section index"].exists)
        XCTAssertFalse(app.buttons["calendar-jump-month-12"].exists)
        app.buttons["calendar-year"].tap()
        app.buttons["calendar-jump-month-12"].tap()
        XCTAssertTrue(app.buttons["calendar-month-1448-12"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar-month-1448-12"].isHittable)
        XCTAssertFalse(app.buttons["calendar-jump-month-12"].exists)
        app.buttons["calendar-year"].tap()
        app.buttons["calendar-jump-month-1"].tap()
        let header = app.buttons["calendar-month-1448-1"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.isHittable)
        let top = header.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(header.isHittable)
        XCTAssertEqual(header.frame.minY, top, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Month menu and sticky header"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor private func checkCalendar(accessibilityText: Bool) throws {
        continueAfterFailure = false
        for language in ["en", "ar"] {
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
            app.buttons[language == "ar" ? "تم" : "Done"].tap()
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
            app.terminate()
        }
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
    @MainActor func testCalendarAdjustmentInEverySupportedLanguage() {
        let languages: [(String, String, String, String)] = [
            ("en", "Calendar", "Adjust this month", "Adjust month"),
            ("ar", "التقويم", "تعديل هذا الشهر", "تعديل الشهر"),
            ("fr", "Calendrier", "Ajuster ce mois", "Ajuster le mois"),
            ("de", "Kalender", "Diesen Monat anpassen", "Monat anpassen"),
            ("id", "Kalender", "Sesuaikan bulan ini", "Sesuaikan bulan"),
            ("it", "Calendario", "Regola questo mese", "Regola mese"),
            ("ja", "カレンダー", "この月を調整", "月を調整"),
            ("ms", "Kalendar", "Laraskan bulan ini", "Laraskan bulan"),
            ("fa", "تقویم", "تنظیم این ماه", "تنظیم ماه"),
            ("ru", "Календарь", "Скорректировать этот месяц", "Скорректировать месяц"),
            ("es", "Calendario", "Ajustar este mes", "Ajustar mes"),
            ("tr", "Takvim", "Bu ayı ayarla", "Ayı ayarla"),
            ("ur", "تقویم", "یہ مہینہ درست کریں", "مہینہ درست کریں"),
            ("zh-Hans", "日历", "调整本月", "调整月份"),
            ("zh-Hant", "行事曆", "調整本月", "調整月份"),
        ]
        for (language, calendar, _, title) in languages {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let tab = app.descendants(matching: .any).matching(identifier: calendar).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), language)
            tab.tap()
            openAdjustments(app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), language)
            XCTAssertTrue(app.steppers["month-offset"].exists, language)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Month adjustment \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    @MainActor func testCalendarMethodAndLocalizedSaudiCountry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let method = app.buttons["calendar-method"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.tap()
        app.buttons["Local naked eye"].tap()
        XCTAssertTrue(app.staticTexts["Middle East"].exists)
        XCTAssertFalse(app.buttons["calendar-country"].exists)
        method.tap()
        app.buttons["Government announcement"].tap()
        let country = app.descendants(matching: .any).matching(identifier: "calendar-country").firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 5))
        XCTAssertTrue(country.label.contains("Saudi Arabia"))
        XCTAssertFalse(app.buttons["calendar-country"].exists)
        method.tap()
        app.buttons["System calendar"].tap()
        XCTAssertFalse(app.buttons["calendar-country"].exists)
    }
}

extension CalendarUITests {
    @MainActor func testMonthAdjustmentAtAccessibilityTextSize() {
        for (language, calendar, _, save) in [
            ("de", "Kalender", "Diesen Monat anpassen", "Sichern"),
            ("ur", "تقویم", "یہ مہینہ درست کریں", "محفوظ کریں"),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let tab = app.descendants(matching: .any).matching(identifier: calendar).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            openAdjustments(app)
            let adjustment = app.steppers["month-offset"]
            XCTAssertTrue(adjustment.waitForExistence(timeout: 5))
            let button = adjustment.buttons.element(boundBy: 0)
            for _ in 0 ..< 5 {
                if button.isHittable {
                    break
                }
                app.swipeUp()
            }
            XCTAssertTrue(button.isHittable)
            button.tap()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Month adjustment large text \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons[save].tap()
            XCTAssertTrue(app.buttons["month-adjustments"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
