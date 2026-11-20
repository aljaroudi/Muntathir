import Foundation
@testable import Muntathir
import Testing

struct ReleaseNotesTests {
    @Test func bundledHistoryAndUpdateRange() {
        let history = ReleaseNote.history
        #expect(history.contains { $0.version == "1.0.0" })
        #expect(ReleaseNote.hasUnseenNotes(since: "", installed: "1.1.1", history: history))
        #expect(ReleaseNote.hasUnseenNotes(since: "1.0.0", installed: "1.1.1", history: history))
        #expect(!ReleaseNote.hasUnseenNotes(since: "1.1.1", installed: "1.1.1", history: history))
        #expect(!ReleaseNote.hasUnseenNotes(since: "", installed: "1.10.0", history: history))
    }

    @Test func resolvesScriptAndEnglishFallback() {
        let entry = ReleaseNote(version: "1.0.0", platforms: ["ios"], notes: ["en-US": "en", "zh-Hans": "Hans", "zh-Hant": "Hant"])
        #expect(entry.text(for: Locale(identifier: "zh_TW")) == "Hant")
        #expect(entry.text(for: Locale(identifier: "zh_CN")) == "Hans")
        #expect(entry.text(for: Locale(identifier: "sv_SE")) == "en")
    }
}
