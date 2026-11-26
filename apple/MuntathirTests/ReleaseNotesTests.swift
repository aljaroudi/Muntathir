import Foundation
@testable import Muntathir
import Testing

struct ReleaseNotesTests {
    @Test func bundledHistoryAndUpdateRange() {
        let history = ReleaseNote.history
        #expect(history.contains { $0.version == "1.0.0" })
        #expect(ReleaseNote.hasUnseenNotes(since: "", installed: "1.1.0", history: history))
        #expect(ReleaseNote.hasUnseenNotes(since: "1.0.0", installed: "1.1.0", history: history))
        #expect(!ReleaseNote.hasUnseenNotes(since: "1.1.0", installed: "1.1.0", history: history))
        #expect(!ReleaseNote.hasUnseenNotes(since: "", installed: "1.10.0", history: history))
    }

    @Test func parsesReleaseDayInAnyTimeZone() throws {
        let entry = ReleaseNote(version: "1.0.0", platforms: ["ios"], notes: [:], releaseDates: ["ios": "2026-11-06"])
        let day = try #require(entry.releaseDate)
        #expect(day.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "en_US"), timeZone: .gmt)) == "11/6/2026")
        #expect(ReleaseNote(version: "1.2.0", platforms: ["ios"], notes: [:]).releaseDate == nil)
    }

    @Test func resolvesScriptAndEnglishFallback() {
        let entry = ReleaseNote(version: "1.0.0", platforms: ["ios"], notes: ["en-US": ["en"], "zh-Hans": ["Hans"], "zh-Hant": ["Hant"]])
        #expect(entry.items(for: Locale(identifier: "zh_TW")) == ["Hant"])
        #expect(entry.items(for: Locale(identifier: "zh_CN")) == ["Hans"])
        #expect(entry.items(for: Locale(identifier: "sv_SE")) == ["en"])
    }
}
