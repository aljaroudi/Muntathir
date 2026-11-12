import Foundation
@testable import Muntathir
import Testing

struct QuranPageTextTests {
    private var database: QuranDatabase {
        QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"))
    }

    @Test func everyQPCWordMapsToCanonicalTextExceptVerseNumbers() throws {
        for number in 1 ... QuranPage.count {
            let page = try database.page(number)
            let content = QuranPageText(page: page, surahs: [])
            let original = page.lines.flatMap(\.words)
            #expect(content.words.count == original.count)
            for (word, source) in zip(content.words, original) {
                let verse = try #require(content.verses[word.source])
                #expect((content.text as NSString).substring(with: word.display) == source.text)
                let isMarker = source.text.allSatisfy(\.isNumber)
                if let range = word.canonical {
                    #expect(!isMarker)
                    #expect(HighlightRange(range, in: verse.text) != nil)
                } else {
                    #expect(isMarker, "Unmapped word on page \(number): \(source.text)")
                }
            }
        }
    }

    @Test func selectionCrossesLinesAndVersesAndKeepsSpaces() throws {
        let content = try QuranPageText(page: database.page(1), surahs: [])
        let first = try #require(content.words.first)
        let last = try #require(content.words.last { $0.source == "1:2" && $0.canonical != nil })
        let selection = NSUnionRange(first.display, last.display)
        let highlights = content.highlights(in: [selection])
        #expect(highlights.map(\.source) == ["1:1", "1:2"])
        for value in highlights {
            let verse = try #require(content.verses[value.source])
            #expect(value.ranges.count == 1)
            #expect(value.ranges.first?.quote == verse.text)
            let rendered = content.displayRanges(for: value)
            #expect(rendered.count == 1)
            #expect((content.text as NSString).substring(with: rendered[0]).contains(" "))
        }
    }

    @Test func highlightEligibilityRequiresSelectedVerseText() throws {
        let content = try QuranPageText(page: database.page(1), surahs: QuranSurah.load())
        let word = try #require(content.words.first { $0.canonical != nil })
        let marker = try #require(content.words.first { $0.canonical == nil })
        let heading = try #require(content.lines.first { $0.kind == .surahName })
        #expect(!content.canHighlight([]))
        #expect(!content.canHighlight([heading.range]))
        #expect(!content.canHighlight([marker.display]))
        #expect(!content.canHighlight([NSRange(location: NSMaxRange(word.display), length: 1)]))
        #expect(content.canHighlight([word.display]))
        #expect(content.canHighlight([heading.range, word.display, marker.display]))
        #expect(content.canHighlight([NSRange(location: word.display.location, length: 1)]))
    }

    @Test func disjointWordsDoNotHighlightTheWordBetweenThem() throws {
        let content = try QuranPageText(page: database.page(1), surahs: [])
        let words = content.words.filter { $0.source == "1:1" && $0.canonical != nil }
        let highlight = try #require(content.highlights(in: [words[0].display, words[2].display]).first)
        #expect(highlight.ranges.count == 2)
        let ranges = content.displayRanges(for: highlight)
        #expect(ranges.count == 2)
        #expect(ranges.allSatisfy { NSIntersectionRange($0, words[1].display).length == 0 })
    }

    @Test func joinedSpellingMapsToBothCanonicalWords() throws {
        let pageNumber = try #require(try database.page(surah: 37, verse: 130))
        let content = try QuranPageText(page: database.page(pageNumber), surahs: [])
        let word = try #require(content.words.last { $0.source == "37:130" && $0.canonical != nil })
        let highlight = try #require(content.highlights(in: [word.display]).first)
        #expect(highlight.excerpt == "إِل ياسينَ")
        #expect(content.displayRanges(for: highlight) == [word.display])
    }

    @Test func partialWordSelectionsRetainCharacterBoundariesAcrossDiacritics() throws {
        let content = try QuranPageText(page: database.page(1), surahs: [])
        let word = try #require(content.words.first { $0.source == "1:1" && $0.canonical != nil })
        let display = (content.text as NSString).substring(with: word.display)
        let firstCharacter = try #require(display.first)
        let selection = NSRange(location: word.display.location, length: String(firstCharacter).utf16.count)
        let saved = try #require(content.highlights(in: [selection]).first)
        #expect(saved.excerpt == "بِ")
        #expect(content.displayRanges(for: saved) == [selection])
    }

    @Test func pageFragmentDoesNotSelectTheRestOfTheVerse() throws {
        let content = try QuranPageText(page: database.page(43), surahs: [])
        let first = try #require(content.words.first)
        let verse = try #require(content.verses[first.source])
        let highlight = try #require(content.highlights(in: [first.display]).first)
        #expect(highlight.ranges.count == 1)
        #expect(highlight.excerpt != verse.text)
        #expect(content.displayRanges(for: highlight) == [first.display])
        let marker = try #require(content.words.first { $0.canonical == nil })
        #expect(content.highlights(in: [marker.display]).isEmpty)
        #expect(content.sources(in: [marker.display]) == [marker.source])
    }
}
