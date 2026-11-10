import Foundation
@testable import Muntathir
import Testing
import UIKit

struct HadithContentsTests {
    @Test func parsesOnlyStandaloneReferences() {
        for query in ["123", " ١ ٢ ٣ ", "۱۲۳"] {
            #expect(HadithSearch.number(query) == 123)
        }
        for query in ["0", "-1", "1.2", "²", "123 prayer"] {
            #expect(HadithSearch.number(query) == nil)
        }
        for query in ["ch3", "CH٣", " ج۳ "] {
            #expect(HadithSearch.chapter(query) == 3)
        }
        for query in ["ch3 prayer", "ج ٣", "ch0", "chapter 3"] {
            #expect(HadithSearch.chapter(query) == nil)
        }
    }

    @Test func groupsUseSourceIdentityAndKeepOrder() {
        let chapters = [
            HadithChapter(id: 9, arabic: "الإيمان", english: "Faith", bookArabic: "كتاب", bookEnglish: "Book", bookID: "second", count: 12),
            HadithChapter(id: 2, arabic: "", english: "Prayer", bookArabic: "كتاب", bookEnglish: "Book", bookID: "second", count: 5),
            HadithChapter(id: 1, arabic: "الإيمان", english: "Faith", bookArabic: "كتاب", bookEnglish: "Book", bookID: "first", count: 7),
        ]
        let groups = HadithContentsGroup.groups(chapters)
        #expect(groups.map(\.id) == ["second", "first"])
        #expect(groups[0].chapters.map(\.id) == [9, 2])
        #expect(HadithContentsGroup.groups(chapters, matching: "إيمان").map(\.id) == ["second", "first"])
        #expect(HadithContentsGroup.groups(chapters, matching: "Prayer").first?.chapters.map(\.id) == [2])
        #expect(chapters[1].chapterTitle(locale: Locale(identifier: "ar")) == "Prayer")
        #expect(HadithContentsGroup.groups(chapters, matching: "missing").isEmpty)
    }

    @Test func contentsLoadNarrationChaptersWithIdentityAndCounts() async throws {
        let fixture = try HadithFixture(count: 3)
        defer { fixture.remove() }
        let chapters = try await HadithReader(database: HadithDatabase(url: fixture.url)).chapters(collectionID: "merged")
        #expect(chapters.map(\.bookID) == ["v1"])
        #expect(chapters.map(\.count) == [3])
        #expect(chapters.map(\.index) == [0])
        #expect(chapters.map(\.collectionID) == ["merged"])
    }

    @Test func oldSessionsDecodeWithoutNavigationFields() throws {
        let saved = HadithSessionState(request: HadithRequest(collectionID: "bukhari", chapterID: 1))
        let data = try JSONEncoder().encode(saved)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["screen", "contentsQuery", "contentsOffset", "listRow", "contentsRow"] {
            object.removeValue(forKey: key)
        }
        let restored = try JSONDecoder().decode(HadithSessionState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.request == saved.request)
        #expect(restored.screen == nil)
    }

    @Test @MainActor func lateefIsBundledAndUsedOnlyForHadith() {
        #expect(UIFont(name: "Lateef-Light", size: 28) != nil)
        let hadith = HighlightTextContent.attributed(text: "نص", markdown: nil, arabic: true, hadith: true, size: 28, alignment: .natural)
        let quran = HighlightTextContent.attributed(text: "نص", markdown: nil, arabic: true, size: 28, alignment: .natural)
        #expect((hadith.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontName == "Lateef-Light")
        #expect((quran.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontName == "KFGQPCHAFSUthmanicScript-Regula")
    }
}
