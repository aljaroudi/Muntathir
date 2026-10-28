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

    @MainActor func testCalendarMethodAndLocalizedCountries() throws {
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
        let country = app.buttons["calendar-country"]
        country.tap()
        for code in ["SA", "KW", "BH", "OM", "AE", "QA"] {
            let name = try XCTUnwrap(Locale(identifier: "en_US").localizedString(forRegionCode: code))
            XCTAssertTrue(app.buttons[name].exists)
        }
        app.buttons["Qatar"].tap()
        XCTAssertTrue(country.label.contains("Qatar"))
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
