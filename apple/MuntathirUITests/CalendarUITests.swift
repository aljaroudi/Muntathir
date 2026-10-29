import XCTest

final class CalendarUITests: XCTestCase {
    @MainActor func testCalendarCollapseSelectionAndEventDates() throws {
        try checkCalendar(accessibilityText: false)
    }

    @MainActor func testCalendarEventDatesAtAccessibilityTextSize() throws {
        try checkCalendar(accessibilityText: true)
    }

    @MainActor private func checkCalendar(accessibilityText: Bool) throws {
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
            let title = app.buttons["calendar-month-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let currentMonth = title.label
            let todayButton = app.buttons["calendar-day-21"]
            XCTAssertFalse(todayButton.exists)
            XCTAssertEqual(title.value as? String, language == "ar" ? "مطوي" : "Collapsed")
            let previous = language == "ar" ? "الشهر السابق" : "Previous month"
            let next = language == "ar" ? "الشهر التالي" : "Next month"
            app.buttons[previous].tap()
            XCTAssertNotEqual(title.label, currentMonth)
            XCTAssertFalse(todayButton.exists)
            app.buttons[next].tap()
            XCTAssertEqual(title.label, currentMonth)
            title.tap()
            XCTAssertEqual(title.value as? String, language == "ar" ? "موسّع" : "Expanded")
            if !accessibilityText {
                XCTAssertTrue(todayButton.isSelected)
            }
            title.tap()
            XCTAssertFalse(todayButton.exists)
            title.tap()
            let eventDay = app.buttons["calendar-day-1"]
            XCTAssertTrue(eventDay.waitForExistence(timeout: 5))
            eventDay.tap()
            XCTAssertFalse(eventDay.isSelected)
            if !accessibilityText {
                XCTAssertTrue(todayButton.isSelected)
            }
            title.tap()
            assertEventDates(app, calendar: calendar, locale: locale, date: firstDay)

            app.buttons[language == "ar" ? "تعديل هذا الشهر" : "Adjust this month"].tap()
            let stepper = app.steppers["month-offset"]
            XCTAssertTrue(stepper.waitForExistence(timeout: 5))
            stepper.buttons.element(boundBy: 1).tap()
            app.buttons[language == "ar" ? "حفظ" : "Save"].tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap()
            eventDay.tap()
            title.tap()
            let correctedFirstDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: firstDay))
            assertEventDates(app, calendar: calendar, locale: locale, date: correctedFirstDay)
            XCTAssertFalse(app.descendants(matching: .any)["calendar-events-2"].exists)
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
        let firstDay = calendar.date(from: DateComponents(year: 1448, month: 9, day: 1))!
        let row = app.staticTexts.matching(identifier: "calendar-events-1")
        let historicalYear = locale.language.languageCode?.identifier == "ar" ? "٢٠٠ هـ" : "200 AH"
        let expectedHijri = "\(1.formatted(.number.locale(locale))) \(formatter.string(from: firstDay)) \(historicalYear)"
        let hijri = row.matching(NSPredicate(format: "label CONTAINS %@", formatter.string(from: firstDay))).firstMatch
        XCTAssertTrue(hijri.waitForExistence(timeout: 5), file: file, line: line)
        let hijriLabel = hijri.label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(hijriLabel, expectedHijri, file: file, line: line)
        XCTAssertTrue(hijri.isHittable, file: file, line: line)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        let civil = row.matching(NSPredicate(format: "label == %@", formatter.string(from: date))).firstMatch
        XCTAssertEqual(civil.label, formatter.string(from: date), file: file, line: line)
        XCTAssertTrue(civil.isHittable, file: file, line: line)
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        XCTAssertTrue(row.matching(NSPredicate(format: "label == %@", formatter.string(from: date))).firstMatch.exists, file: file, line: line)
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
        for (language, calendar, adjust, title) in languages {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let tab = app.descendants(matching: .any).matching(identifier: calendar).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), language)
            tab.tap()
            app.buttons[adjust].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), language)
            XCTAssertTrue(app.steppers["month-offset"].exists, language)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Month adjustment \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    @MainActor func testCalendarMethodAndLocalizedSaudiCountry() throws {
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
        for (language, calendar, adjust, save) in [
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
            app.buttons[adjust].tap()
            XCTAssertTrue(app.steppers["month-offset"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.steppers["month-offset"].isHittable)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Month adjustment large text \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons[save].tap()
            XCTAssertTrue(app.navigationBars[calendar].waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
