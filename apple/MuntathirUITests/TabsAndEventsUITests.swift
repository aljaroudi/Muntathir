import XCTest

final class TabsAndEventsUITests: XCTestCase {
    @MainActor private func launch(language: String = "en", largeText: Bool = false, arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-mecca", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture",
                               "--sky-date", "2026-10-23T06:00:00Z",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_SA" : "en_US"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + arguments
        app.launch()
        return app
    }

    @MainActor func testCustomizeTabsAndRestoreOnToday() {
        let app = launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected)
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        app.buttons["add-tab-events"].tap()
        app.buttons["add-tab-hadith"].tap()
        XCTAssertFalse(app.buttons["add-tab-quran"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Events"].firstMatch.tap()
        let event = app.buttons["observance-husayn-arrival-karbala"]
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        event.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-husayn-ibn-ali"].firstMatch.waitForExistence(timeout: 10))
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        let reorder = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Reorder'"))
        XCTAssertTrue(reorder.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(reorder.count, 3)
        reorder.element(boundBy: 1).press(forDuration: 1, thenDragTo: reorder.element(boundBy: 0))
        let calendar = app.cells.containing(.any, identifier: "tab-shortcut-calendar").firstMatch
        XCTAssertLessThan(app.cells.containing(.any, identifier: "tab-shortcut-events").firstMatch.frame.minY, calendar.frame.minY)
        calendar.images["minus.circle.fill"].firstMatch.tap()
        if app.buttons["Delete"].waitForExistence(timeout: 1) {
            app.buttons["Delete"].firstMatch.tap()
        }
        XCTAssertFalse(app.staticTexts["tab-shortcut-calendar"].exists)
        XCTAssertTrue(app.buttons["add-tab-quran"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["calendar"].exists)
        XCTAssertFalse(app.buttons["events"].exists)
        XCTAssertFalse(app.buttons["hadith"].exists)
        app.buttons["Events"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-husayn-ibn-ali"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["events-month-1"].waitForExistence(timeout: 5))
        app.buttons["Hadith"].firstMatch.tap()
        XCTAssertTrue(app.buttons["hadith-book-bukhari"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected)
        XCTAssertTrue(app.buttons["Events"].exists)
        XCTAssertTrue(app.buttons["Hadith"].exists)
        XCTAssertFalse(app.buttons["Calendar"].exists)
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        let rows = app.cells.allElementsBoundByIndex.filter { $0.staticTexts["tab-shortcut-events"].exists || $0.staticTexts["tab-shortcut-hadith"].exists }
        XCTAssertEqual(rows.count, 2)
        XCTAssertLessThan(app.cells.containing(.any, identifier: "tab-shortcut-events").firstMatch.frame.minY,
                          app.cells.containing(.any, identifier: "tab-shortcut-hadith").firstMatch.frame.minY)
    }

    @MainActor func testEventsStartAtMuharramAndOpenFigure() {
        let app = launch()
        app.buttons["Tools"].firstMatch.tap()
        app.buttons["events"].tap()
        XCTAssertTrue(app.staticTexts["events-month-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar-year"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["calendar-countdown"].exists)
        let event = app.buttons["observance-husayn-arrival-karbala"]
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        event.tap()
        XCTAssertTrue(app.descendants(matching: .any)["figure-profile-husayn-ibn-ali"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testRakaatShortcutCanSwitchTabsBeforeAndAfterSession() {
        let app = launch(arguments: ["--rakaat-denied"])
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        let addRakaat = app.buttons["add-tab-rakaat"]
        for _ in 0 ..< 5 where !addRakaat.isHittable {
            app.swipeUp()
        }
        addRakaat.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let rakaatTab = app.buttons["Rakaat Tracker"].firstMatch
        let todayTab = app.buttons["Today"].firstMatch
        let target = app.buttons["rakaat-target-2"]
        rakaatTab.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(todayTab.isHittable)
        todayTab.tap()
        XCTAssertTrue(todayTab.isSelected)

        rakaatTab.tap()
        target.tap()
        app.buttons["rakaat-prayer-other"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(todayTab.isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(todayTab.isHittable)
        todayTab.tap()
        XCTAssertTrue(todayTab.isSelected)
    }

    @MainActor func testQuranNavigationSurvivesTabReordering() {
        let app = launch()
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        app.buttons["add-tab-quran"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Holy Quran"].firstMatch.tap()
        XCTAssertTrue(app.buttons["quran-saved"].waitForExistence(timeout: 10))
        app.buttons["quran-saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        let reorder = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Reorder'"))
        reorder.element(boundBy: 1).press(forDuration: 1, thenDragTo: reorder.element(boundBy: 0))
        app.buttons["Holy Quran"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
    }

    @MainActor func testArabicEventsAndTabsAtAccessibilitySize() {
        let app = launch(language: "ar", largeText: true)
        app.buttons["الأدوات"].firstMatch.tap()
        // Section headers push Events below the fold at accessibility sizes.
        let events = app.buttons["events"]
        for _ in 0 ..< 5 where !events.isHittable {
            app.swipeUp()
        }
        events.tap()
        let month = app.staticTexts["events-month-1"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertTrue(month.label.contains("محرم"))
        XCTAssertTrue(app.buttons["observance-husayn-arrival-karbala"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Arabic Events at accessibility size"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        let addEvents = app.buttons["add-tab-events"]
        for _ in 0 ..< 5 where !addEvents.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addEvents.isHittable)
        addEvents.tap()
        XCTAssertTrue(app.buttons["المناسبات"].exists)
    }
}
