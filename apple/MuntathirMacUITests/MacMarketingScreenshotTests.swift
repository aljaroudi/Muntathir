import AppKit
import XCTest

/// Mac App Store captures. fastlane snapshot only drives iOS simulators, so each screen is kept as an
/// XCTAttachment named `Mac-<screen>`; fastlane/ios/mac_screenshots.rb exports them from the result bundle.
final class MacMarketingScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The runner otherwise reaches XCTest's display lookups (clicks, element screenshots)
        // without a window server connection and aborts in CGS_REQUIRE_INIT.
        _ = NSScreen.screens
    }

    /// Set per run with TEST_RUNNER_MUNTATHIR_CAPTURE_LOCALE, for example "ar-SA".
    private var captureLocale: String {
        ProcessInfo.processInfo.environment["MUNTATHIR_CAPTURE_LOCALE"] ?? "en-US"
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let locale = Locale(identifier: captureLocale)
        let language = locale.language.languageCode?.identifier == "zh"
            ? "zh-\(locale.language.script?.identifier ?? "Hans")"
            : locale.language.languageCode?.identifier ?? "en"
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", captureLocale.replacingOccurrences(of: "-", with: "_"),
            "-AppleInterfaceStyle", "Light", "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
            // AppKit otherwise opens values like "clear" as documents, and the app then skips its main window.
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--marketing-local-translations", "--screenshot-verse",
            "--sky-date", "2026-10-23T06:00:00Z", "--ui-testing-weather", "--weather-condition", "clear",
        ]
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 15) {
            // Record the screen so a missing window (for example behind a system prompt) can be diagnosed.
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "Screen without capture window"
            screen.lifetime = .keepAlways
            add(screen)
            XCTFail("Muntathir opened no window; see the screen attachment")
        }
        // The window restores its last tab, so start every launch on Today (the first sidebar row).
        let today = app.outlines.firstMatch.cells.firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.click()
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String, settle: UInt32 = 2) {
        // Keep the pointer out of the shot, then let loading, scroll and selection animations settle.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 0.5)).hover()
        sleep(settle)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Mac-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The app's translation of `key` in the capture language, read from the built app beside the runner.
    private func appString(_ key: String) -> String {
        let locale = Locale(identifier: captureLocale)
        let code = locale.language.languageCode?.identifier ?? "en"
        let localization = code == "zh" ? "zh-\(locale.language.script?.identifier ?? "Hans")" : code
        let app = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Muntathir.app")
        guard let strings = Bundle(url: app)?.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: localization),
              let table = NSDictionary(contentsOf: strings) as? [String: String]
        else { return key }
        return table[key] ?? key
    }

    /// Sidebar rows on macOS expose their title, not the tool's accessibility identifier.
    @MainActor private func open(_ app: XCUIApplication, tool title: String) {
        let text = appString(title)
        let row = app.outlines.firstMatch.cells.containing(NSPredicate(format: "value == %@ OR label == %@", text, text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Missing sidebar item \(text)")
        row.click()
    }

    /// Scrolls the detail content until the element can be clicked.
    @MainActor private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 12 where !(target.exists && target.isHittable) {
            app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        }
        XCTAssertTrue(target.isHittable)
    }

    @MainActor func testStoreScreenshots() throws {
        continueAfterFailure = false
        let labels = try marketingLabels(for: captureLocale)

        var app = launch()
        XCTAssertTrue(element(app, "prayer-fajr").waitForExistence(timeout: 15))
        let verse = element(app, "daily-ayah-text")
        XCTAssertTrue(verse.waitForExistence(timeout: 5))
        XCTAssertEqual(verse.value as? String ?? verse.label, "إِنَّ مَعَ العُسرِ يُسرًا")
        capture(app, "01-Today")

        open(app, tool: "Calendar")
        XCTAssertTrue(app.buttons["calendar-jump"].waitForExistence(timeout: 5))
        // The fixed capture date is 1448-05; show Sha'ban for the store listing.
        app.buttons["calendar-jump"].click()
        for _ in 0 ..< 3 {
            app.buttons[labels[1]].firstMatch.click()
        }
        let day = app.buttons["calendar-day-1448-8-1"]
        reveal(day, in: app)
        day.click()
        capture(app, "09-Calendar")

        open(app, tool: "Holy Quran")
        // Capture builds already select each locale's translation at launch, so the reading options stay closed.
        let result = element(app, "quran-result-94:6")
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        reveal(result, in: app)
        result.click()
        XCTAssertTrue(element(app, "quran-verse-94:6").waitForExistence(timeout: 10))
        if Locale(identifier: captureLocale).language.languageCode?.identifier != "ar" {
            XCTAssertTrue(element(app, "quran-translation-94:6").waitForExistence(timeout: 10))
        }
        capture(app, "02-Quran", settle: 6)
        app.terminate()

        app = launch()
        open(app, tool: "Hadith")
        XCTAssertTrue(element(app, "hadith-saved").waitForExistence(timeout: 15))
        let book = app.buttons["hadith-book-bukhari"]
        reveal(book, in: app)
        book.click()
        let chapter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-chapter-")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hadith-result-")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "03-Hadith", settle: 6)

        open(app, tool: "Supplications")
        XCTAssertTrue(element(app, "supplication-1").waitForExistence(timeout: 15))
        capture(app, "05-Supplications")

        open(app, tool: "Tasbih")
        XCTAssertTrue(element(app, "tasbih-count").waitForExistence(timeout: 5))
        capture(app, "06-Tasbih")
        app.terminate()
    }
}
