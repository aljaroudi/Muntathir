import XCTest

extension XCUIApplication {
    /// With a tab sidebar (iPad, unfolded Duo), tabs and tools are sidebar rows and there is no Tools tab.
    /// The floating tab bar shows `ToggleSideBar`; the open sidebar shows `ToggleSidebar`.
    @MainActor var usesTabSidebar: Bool {
        // Poll for either layout's marker; the Settings sheet hides the tab bar but shows Done.
        let deadline = Date.now.addingTimeInterval(15)
        repeat {
            if buttons["ToggleSideBar"].exists || buttons["ToggleSidebar"].exists {
                return true
            }
            if buttons["square.grid.2x2"].exists || buttons["settings-done"].exists {
                return false
            }
        } while Date.now < deadline
        return false
    }

    @MainActor func showTabSidebar() {
        let hide = buttons["ToggleSidebar"]
        guard !hide.exists else { return }
        buttons["ToggleSideBar"].tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
    }

    @MainActor private func selectMainTab(_ identifier: String) {
        let labels = [
            "square.grid.2x2": ["الأدوات", "Werkzeuge", "Tools", "Herramientas", "ابزارها", "Outils", "Alat", "Strumenti", "ツール", "Alatan", "Инструменты", "Araçlar", "اوزار", "工具"],
            "sun.max": ["اليوم", "Heute", "Today", "Hoy", "امروز", "Aujourd’hui", "Hari ini", "Oggi", "今日", "Сегодня", "Bugün", "آج", "今天"],
            "calendar": ["التقويم", "Kalender", "Calendar", "Calendario", "تقویم", "Calendrier", "カレンダー", "Kalendar", "Календарь", "Takvim", "日历", "行事曆"],
        ]
        let predicate = NSPredicate(format: "label IN %@", labels[identifier]!)
        let button = buttons.matching(predicate).firstMatch
        // An open sidebar lists tabs as cells instead of tab-bar buttons.
        (button.exists ? button : cells.matching(predicate).firstMatch).tap()
    }

    /// Opens a tool such as `holy-quran` from the sidebar or, without one, from the Tools tab.
    @MainActor func openTool(_ identifier: String) {
        let row: XCUIElement
        if usesTabSidebar {
            showTabSidebar()
            row = cells[identifier]
            // Large text can push later tools below the sidebar's fold.
            let sidebar = collectionViews.containing(.cell, identifier: "sun.max").firstMatch
            for _ in 0 ..< 6 where !row.isHittable {
                sidebar.swipeUp()
            }
        } else {
            selectMainTab("square.grid.2x2")
            row = buttons[identifier]
        }
        // Large text can push later tools below the fold, where the list hasn't loaded them yet.
        for _ in 0 ..< 6 where !row.waitForExistence(timeout: 1) || !row.isHittable {
            swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
    }

    @MainActor func openSettingsFromTools() {
        // With a sidebar, Settings is its own tab, opened from the sidebar's bottom bar.
        if usesTabSidebar {
            showTabSidebar()
            buttons["settings-tab"].tap()
            // Unlike tool rows, the bottom-bar button leaves the sidebar over the Settings page list.
            let hide = buttons["ToggleSidebar"]
            if hide.waitForExistence(timeout: 1) {
                hide.tap()
            }
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
        // The split layout labels page rows with static texts; the single list uses buttons.
        let page = usesTabSidebar ? staticTexts[identifier] : buttons[identifier]
        // Large text can push later pages below the fold, where the list hasn't loaded them yet.
        for _ in 0 ..< 5 where !page.waitForExistence(timeout: 1) || !page.isHittable {
            swipeUp()
        }
        XCTAssertTrue(page.isHittable)
        page.tap()
    }

    /// Dismisses the Settings sheet from any of its pages; with a sidebar, Settings is a tab and stays open.
    @MainActor func closeSettings() {
        guard !usesTabSidebar else { return }
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
