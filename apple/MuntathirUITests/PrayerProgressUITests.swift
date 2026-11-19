import XCTest

final class PrayerProgressUITests: XCTestCase {
    @MainActor private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture", "--rakaat-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        return app
    }

    @MainActor private func openTool(_ id: String, app: XCUIApplication) {
        app.buttons["Tools"].firstMatch.tap()
        for _ in 0 ..< 5 where !app.buttons[id].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        app.buttons[id].tap()
    }

    @MainActor func testEmptyHistoryAndShortcut() {
        let app = launch()
        openTool("prayer-progress", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["progress-prayer-chart"].firstMatch.waitForExistence(timeout: 5))
        let chart = app.descendants(matching: .any)["progress-prayer-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        for prayer in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
            XCTAssertTrue((chart.value as? String ?? "").contains("\(prayer): 0"))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSettingsFromTools()
        app.buttons["settings-tabs"].tap()
        for _ in 0 ..< 4 where !app.buttons["add-tab-prayerProgress"].isHittable {
            app.swipeUp()
        }
        app.buttons["add-tab-prayerProgress"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Activity"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Activity"].exists)
    }

    @MainActor func testArabicActivityAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-hadith-fixture", "--ui-testing-supplications-fixture",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["الأدوات"].firstMatch.tap()
        for _ in 0 ..< 6 where !app.buttons["prayer-progress"].isHittable {
            app.swipeUp()
        }
        app.buttons["prayer-progress"].tap()
        XCTAssertTrue(app.navigationBars["النشاط"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["prayer-total-fajr"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Activity — Arabic accessibility"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts["Activity"].exists)
        let card = app.descendants(matching: .any)["progress-tasbih"].firstMatch
        for _ in 0 ..< 12 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        let cards = XCTAttachment(screenshot: app.screenshot())
        cards.name = "Activity cards — Arabic accessibility"
        cards.lifetime = .keepAlways
        add(cards)
    }

    @MainActor func testNamedCompletionPersistsNeutralSummary() {
        let app = launch()
        openTool("rakaat-tracker", app: app)
        app.buttons["rakaat-target-2"].tap()
        XCTAssertTrue(app.buttons["rakaat-prayer-fajr"].exists)
        app.buttons["rakaat-prayer-fajr"].firstMatch.tap()
        XCTAssertTrue(app.buttons["rakaat-complete"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTool("prayer-progress", app: app)
        let marker = app.descendants(matching: .any)["prayer-unavailable-count"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        openTool("prayer-progress", app: app)
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
    }

    @MainActor func testSelectionChoicesAndCancelledPreparation() {
        let app = launch()
        openTool("rakaat-tracker", app: app)
        for (target, choices) in [(2, ["fajr"]), (3, ["maghrib"]), (4, ["dhuhr", "asr", "isha"])] {
            app.buttons["rakaat-target-\(target)"].tap()
            for prayer in choices {
                XCTAssertTrue(app.buttons["rakaat-prayer-\(prayer)"].exists)
            }
            XCTAssertTrue(app.buttons["rakaat-prayer-other"].exists)
            app.buttons["rakaat-prayer-\(choices[0])"].firstMatch.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTool("prayer-progress", app: app)
        let chart = app.descendants(matching: .any)["progress-prayer-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(chart.value as? String, "Fajr: 0, Dhuhr: 0, Asr: 0, Maghrib: 0, Isha: 0")
        XCTAssertFalse(app.descendants(matching: .any)["prayer-outsideTime-count"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["prayer-unavailable-count"].firstMatch.exists)
    }

    @MainActor func testPopulatedDashboard() {
        let app = launch(["--ui-testing-progress-fixture", "--ui-testing-legacy-highlights"])
        openTool("prayer-progress", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["progress-prayer-chart"].firstMatch.exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Activity overview"
        overview.lifetime = .keepAlways
        add(overview)
        for _ in 0 ..< 4 where !app.descendants(matching: .any)["progress-highlights"].firstMatch.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(app.descendants(matching: .any)["progress-highlights"].firstMatch.value as? String, "2")
        let tasbih = app.descendants(matching: .any)["progress-tasbih"].firstMatch
        for _ in 0 ..< 4 where !tasbih.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(tasbih.value as? String, "1,234")
    }

    @MainActor func testPartialTasbihPersistsAcrossVisits() {
        let app = launch()
        openTool("tasbih", app: app)
        let beads = app.descendants(matching: .any)["tasbih-beads"].firstMatch
        for _ in 0 ..< 2 {
            let start = beads.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTool("prayer-progress", app: app)
        let count = app.descendants(matching: .any)["progress-tasbih"].firstMatch
        for _ in 0 ..< 4 where !count.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(count.value as? String, "2")
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        openTool("prayer-progress", app: app)
        for _ in 0 ..< 4 where !count.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(count.value as? String, "2")
    }

    @MainActor func testReadingTimeIsAttributedToEachReader() {
        // Each reader tracks its own kind, so verse-mode readers share a launch; Mushaf needs its own reading mode.
        for (mode, readers) in [("verses", [("hadith", "hadithReading"), ("supplications", "supplicationReading"), ("holy-quran", "quranReading")]),
                                ("mushaf", [("holy-quran", "quranReading")])]
        {
            let app = launch(["-quranReadingMode", mode])
            for (tool, kind) in readers {
                checkReadingTime(tool: tool, kind: kind, mode: mode, app: app)
            }
            app.terminate()
        }
    }

    @MainActor private func checkReadingTime(tool: String, kind: String, mode: String, app: XCUIApplication) {
        openTool(tool, app: app)
        if tool == "hadith" {
            app.buttons["hadith-book-bukhari"].tap()
            app.openFirstHadithChapter()
            let row = app.buttons["hadith-result-1"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
        } else if tool == "supplications" {
            let row = app.buttons["supplication-1"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
        } else {
            let row = app.buttons["quran-surah-1"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
        }
        let text = app.descendants(matching: .any)[tool == "holy-quran" ? (mode == "mushaf" ? "quran-page-text-1" : "quran-verse-1:1") : "hadith-full-arabic"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        app.swipeUp()
        app.swipeDown()
        app.buttons["Today"].firstMatch.tap()
        app.buttons["Tools"].firstMatch.tap()
        // Return from the retained reader stack to the Tools root.
        for _ in 0 ..< 6 where !app.buttons["prayer-progress"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        openTool("prayer-progress", app: app)
        let card = app.descendants(matching: .any)["progress-\(kind)"].firstMatch
        for _ in 0 ..< 4 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.exists)
        let duration = card.value as? String ?? ""
        XCTAssertTrue(duration.contains { ($0.wholeNumberValue ?? 0) > 0 }, "Expected recorded reading time, got \(duration)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
