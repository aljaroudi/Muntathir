import Foundation
@testable import Muntathir
import Testing

@MainActor struct SearchHistoryTests {
    @Test func historyPersistsOrdersAndSeparatesAreas() throws {
        let suite = "SearchHistoryTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistory(defaults: defaults)
        history.record("  mercy\n", in: .quran)
        history.record("patience", in: .quran)
        history.record("mercy", in: .quran)
        history.record(" \n ", in: .quran)
        history.record("mercy", in: .hadith)
        #expect(history.queries(in: .quran) == ["mercy", "patience"])
        #expect(history.queries(in: .hadith) == ["mercy"])
        #expect(history.queries(in: .supplications).isEmpty)
        #expect(SearchHistory(defaults: defaults).queries(in: .quran) == ["mercy", "patience"])
        history.remove("mercy", from: .quran)
        #expect(history.queries(in: .quran) == ["patience"])
        history.clear(.quran)
        #expect(SearchHistory(defaults: defaults).queries(in: .quran).isEmpty)
        #expect(history.queries(in: .hadith) == ["mercy"])
    }

    @Test func historyKeepsTwentyMostRecentQueries() throws {
        let suite = "SearchHistoryTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistory(defaults: defaults)
        for number in 0 ..< 25 {
            history.record(String(number), in: .figures)
        }
        #expect(history.queries(in: .figures) == (5 ..< 25).reversed().map(String.init))
        history.record("10", in: .figures)
        #expect(history.queries(in: .figures).first == "10")
        #expect(history.queries(in: .figures).count == 20)
    }
}
