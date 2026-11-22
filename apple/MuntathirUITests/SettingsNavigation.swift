import XCTest

extension XCUIApplication {
    @MainActor private func selectMainTab(_ identifier: String) {
        let labels = [
            "square.grid.2x2": ["الأدوات", "Werkzeuge", "Tools", "Herramientas", "ابزارها", "Outils", "Alat", "Strumenti", "ツール", "Alatan", "Инструменты", "Araçlar", "اوزار", "工具"],
            "sun.max": ["اليوم", "Heute", "Today", "Hoy", "امروز", "Aujourd’hui", "Hari ini", "Oggi", "今日", "Сегодня", "Bugün", "آج", "今天"],
            "calendar": ["التقويم", "Kalender", "Calendar", "Calendario", "تقویم", "Calendrier", "カレンダー", "Kalendar", "Календарь", "Takvim", "日历", "行事曆"],
        ]
        buttons.matching(NSPredicate(format: "label IN %@", labels[identifier]!)).firstMatch.tap()
    }

    @MainActor func openSettingsFromTools() {
        // With a sidebar, Settings is its own tab.
        let sidebarSettings = buttons["settings-tab"].firstMatch
        if sidebarSettings.waitForExistence(timeout: 2) {
            sidebarSettings.tap()
            return
        }
        selectMainTab("square.grid.2x2")
        let settings = buttons["settings"]
        for _ in 0 ..< 5 where !settings.isHittable {
            swipeUp()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    @MainActor func leaveSettings(for tab: String = "sun.max") {
        if !buttons["settings-tab"].exists {
            navigationBars.buttons.element(boundBy: 0).tap()
        }
        selectMainTab(tab)
    }
}
