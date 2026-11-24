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
        // Otherwise it's a sheet from the Tools toolbar.
        selectMainTab("square.grid.2x2")
        let settings = buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    /// Opens a page of Settings, such as `settings-prayers`, from either settings layout.
    @MainActor func openSettingsPage(_ identifier: String) {
        openSettingsFromTools()
        let page = buttons[identifier]
        // Large text can push later pages below the fold, where the list hasn't loaded them yet.
        for _ in 0 ..< 5 where !page.waitForExistence(timeout: 1) || !page.isHittable {
            swipeUp()
        }
        XCTAssertTrue(page.isHittable)
        page.tap()
    }

    /// Dismisses the Settings sheet from any of its pages; with a sidebar, Settings is a tab and stays open.
    @MainActor func closeSettings() {
        guard !buttons["settings-tab"].exists else { return }
        let done = buttons["settings-done"]
        let back = navigationBars.buttons["BackButton"]
        // Done only shows on the Settings root, so return there first.
        for _ in 0 ..< 3 where !done.exists && back.exists {
            back.tap()
        }
        if done.waitForExistence(timeout: 2) {
            done.tap()
        }
    }

    @MainActor func leaveSettings(for tab: String = "sun.max") {
        closeSettings()
        selectMainTab(tab)
    }
}
