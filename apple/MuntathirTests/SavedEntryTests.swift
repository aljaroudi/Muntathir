import Foundation
@testable import Muntathir
import Testing

struct SavedEntryTests {
    private let locale = Locale(identifier: "en_US")

    private func highlight(_ id: String, source: String, created: Double, modified: Double) -> ReadingHighlight {
        var value = ReadingHighlight(source: source, isHadith: false, excerpt: "بِسْمِ اللَّهِ", reference: source)
        value.id = id
        value.createdAt = Date(timeIntervalSince1970: created)
        value.modifiedAt = Date(timeIntervalSince1970: modified)
        return value
    }

    @Test func sourceSectionsFollowLatestActivityAndHaveStableTies() {
        let values = [highlight("a", source: "1:1", created: 10, modified: 20),
                      highlight("b", source: "1:2", created: 30, modified: 30),
                      highlight("c", source: "1:1", created: 5, modified: 40),
                      highlight("d", source: "1:1", created: 5, modified: 40)].map(SavedEntry.init)
        let sections = SavedEntry.sections(values, byDate: false, query: "", calendar: .current, locale: locale)
        #expect(sections.map { $0.entries[0].source } == ["1:1", "1:2"])
        #expect(sections[0].entries.map(\.id) == ["highlight:d", "highlight:c", "highlight:a"])
        let reversed = SavedEntry.sections(values.reversed(), byDate: false, query: "", calendar: .current, locale: locale)
        #expect(sections.map(\.id) == reversed.map(\.id))
        #expect(sections[0].entries.map(\.id) == reversed[0].entries.map(\.id))
    }

    @Test func datesUseCreationAndLocalMidnightInsteadOfEdits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 3 * 3600))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)))
        let values = [highlight("yesterday", source: "1:1", created: midnight.timeIntervalSince1970 - 1, modified: midnight.timeIntervalSince1970 + 500),
                      highlight("today", source: "1:1", created: midnight.timeIntervalSince1970, modified: midnight.timeIntervalSince1970)].map(SavedEntry.init)
        let sections = SavedEntry.sections(values, byDate: true, query: "", calendar: calendar, locale: locale)
        #expect(sections.count == 2)
        #expect(sections[0].date == midnight)
        #expect(sections[0].entries[0].id == "highlight:today")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(SavedEntry.sections(values, byDate: true, query: "", calendar: calendar, locale: locale).count == 1)
    }

    @Test func searchNormalizesTextAndFiltersBeforeGrouping() {
        var first = highlight("a", source: "1:1", created: 1, modified: 1)
        first.note = "Café reflection"
        let second = highlight("b", source: "2:1", created: 2, modified: 2)
        let values = [first, second].map(SavedEntry.init)
        #expect(values[0].matches("بسم الله", locale: locale))
        #expect(values[0].matches("CAFE reflection", locale: locale))
        #expect(values[0].matches("1:1", locale: locale))
        #expect(values[0].matches("الفاتحة", locale: Locale(identifier: "ar")))
        let sections = SavedEntry.sections(values, byDate: false, query: "cafe", calendar: .current, locale: locale)
        #expect(sections.count == 1)
        #expect(sections.first?.entries.map(\.id) == ["highlight:a"])
        #expect(SavedEntry.sections(values, byDate: true, query: "missing", calendar: .current, locale: locale).isEmpty)
        #expect(SavedEntry.sections([], byDate: false, query: "", calendar: .current, locale: locale).isEmpty)
    }

    @Test func bookmarksUseSourceAndCreationDateWithoutHighlights() {
        let bookmark = ReadingBookmark(source: "1:1", isHadith: false, excerpt: "Mercy", reference: "1:1")
        let entry = SavedEntry(bookmark)
        #expect(entry.highlight == nil)
        #expect(entry.matches("mercy", locale: locale))
        let narration = SavedEntry(ReadingBookmark(source: "opaque-source-key", isHadith: true, excerpt: "Mercy", reference: "Book 1"))
        #expect(narration.matches("opaque", locale: locale) == false)
        #expect(narration.matches("Book 1", locale: locale))
        #expect(SavedEntry.sections([entry], byDate: true, query: "", calendar: .current, locale: locale).count == 1)
    }
}
