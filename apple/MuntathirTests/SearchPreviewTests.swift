@testable import Muntathir
import SwiftUI
import Testing

struct SearchPreviewTests {
    @Test func previewPrefersTheFullArabicPhrase() {
        let phrase = "من كنت مولاه فعلي"
        let source = String(repeating: "من قبل ", count: 250) + phrase
        let result = HadithText.preview(source, terms: QuranSearchText.terms(phrase))
        #expect(String(result.characters).contains(phrase))
        let filteredTerms = QuranSearchText.queryTerms(phrase)
        #expect(filteredTerms == ["كنت", "مولاه", "فعلي"])
        let filteredResult = HadithText.preview(source, terms: filteredTerms)
        #expect(String(filteredResult.characters).contains(phrase))
    }

    /// The original per-character implementation, kept as the reference the optimized ranges must match.
    private func referenceRanges(in raw: String, terms: [String]) -> [NSRange] {
        var normalized = ""
        var originalRanges: [NSRange] = []
        for index in raw.indices {
            let end = raw.index(after: index)
            let key = QuranSearchText.normalize(String(raw[index ..< end])).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            normalized += key
            originalRanges.append(contentsOf: repeatElement(NSRange(index ..< end, in: raw), count: key.utf16.count))
        }
        let searchable = normalized as NSString
        var ranges: [NSRange] = []
        for term in terms {
            let key = QuranSearchText.normalize(term).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            var offset = 0
            while !key.isEmpty, offset < searchable.length {
                let found = searchable.range(of: key, range: NSRange(location: offset, length: searchable.length - offset))
                guard found.location != NSNotFound, found.length > 0 else { break }
                ranges.append(NSUnionRange(originalRanges[found.location], originalRanges[NSMaxRange(found) - 1]))
                offset = NSMaxRange(found)
            }
        }
        return ranges
    }

    @Test(arguments: [
        ("إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى", "انما الاعمال"),
        ("قال رسول الله ﷺ: الصَّلَاةُ عمود الدين 👨‍👩‍👧‍👦 Prayer is the PILLAR\r\nof faith", "الصلاه pillar"),
        ("Clementísimo, Misericordiosísimo — CAFÉ café", "clementisimo cafe"),
        ("ٱلرَّحْمَٰنِ عَلَّمَ ٱلْقُرْءَانَ", "الرحمن علم"),
    ])
    func fastRangesMatchTheReferenceImplementation(source: String, query: String) {
        let terms = QuranSearchText.terms(query)
        #expect(SearchMatch.ranges(in: source, terms: terms) == referenceRanges(in: source, terms: terms))
        #expect(!SearchMatch.ranges(in: source, terms: terms).isEmpty)
    }

    @Test func longNarrationPreviewIsWindowedAroundTheFirstMatch() {
        let source = String(repeating: "**مقدمة** طويلة جدا ", count: 400) + "إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ" + String(repeating: " خاتمة", count: 400)
        let window = HadithText.previewWindow(source, terms: QuranSearchText.terms("الاعمال"))
        #expect(window.count < 1300)
        #expect(window.contains("الْأَعْمَالُ"))
        let preview = HadithText.preview(source, terms: QuranSearchText.terms("الاعمال"))
        let text = String(preview.characters)
        #expect(text.hasPrefix("… "))
        #expect(text.hasSuffix(" …"))
        #expect(preview.runs.contains { $0.underlineStyle != nil })
        // Short texts are never cut.
        #expect(HadithText.previewWindow("قصير", terms: ["قصير"]) == "قصير")
    }

    @Test func ftsQueryMatchesTheLastWordAsAPrefixFromThreeLetters() {
        #expect(QuranSearchText.ftsQuery(["انما", "الاعم"]).words == "\"انما\" AND \"الاعم\"*")
        #expect(QuranSearchText.ftsQuery(["انما", "الاعم"]).phrase == "\"انما الاعم\"")
        #expect(QuranSearchText.ftsQuery(["ال"]).words == "\"ال\"")
        #expect(QuranSearchText.ftsQuery(["a\"b c"], column: "text").words == "text : \"a\"\"b c\"*")
    }

    @Test func lateMatchKeepsWholeWordsAndHighlight() {
        let source = String(repeating: "Introduction passage. ", count: 30) + "nearby kindness " + String(repeating: "following words ", count: 30)
        let excerpt = SearchMatch.preview(SearchMatch.text(source, query: "kindness"), compact: true)
        let text = String(excerpt.characters)
        #expect(text.hasPrefix("… nearby kindness"))
        #expect(text.hasSuffix(" …"))
        #expect(excerpt.runs.contains { $0.underlineStyle != nil })
        #expect(text.count < 190)
    }

    @Test func unbrokenTextStaysBoundedAndKeepsTheMatchVisible() {
        let source = String(repeating: "a", count: 500) + "needle" + String(repeating: "z", count: 500)
        let excerpt = SearchMatch.preview(SearchMatch.text(source, query: "needle"), compact: true)
        #expect(excerpt.characters.count < 270)
        #expect(String(excerpt.characters).contains("needle"))
    }

    @Test func leadingLineBreaksCannotHideTheMatch() {
        let excerpt = SearchMatch.preview(SearchMatch.text("a\nb\nc\nneedle follows", query: "needle"), compact: true)
        #expect(String(excerpt.characters) == "… needle follows")
    }

    @Test func substringMatchKeepsTheWholeWord() {
        let source = String(repeating: "Opening words ", count: 30) + "uncharacteristically ending"
        let excerpt = SearchMatch.preview(SearchMatch.text(source, query: "istically"), compact: true)
        #expect(String(excerpt.characters).contains("uncharacteristically"))
    }

    @Test func arabicAndUnicodeStayIntact() {
        let source = String(repeating: "مقدمة 👨‍👩‍👧‍👦 ", count: 30) + "الأَعْمَالُ بِالنِّيَّاتِ خاتمة"
        let excerpt = SearchMatch.preview(SearchMatch.text(source, query: "الاعمال"), compact: true)
        #expect(String(excerpt.characters).contains("الأَعْمَالُ"))
        #expect(excerpt.runs.contains { $0.underlineStyle != nil })
    }

    @Test func onlyMatchingBlocksAppearIncludingNotes() {
        let excerpt = SearchMatch.text("A saved passage", query: "kindness")
        let note = SearchMatch.text("My note about kindness", query: "kindness")
        #expect(SearchMatch.visibleBlocks([excerpt, note], preferred: 0) == [1])
        let otherMatch = SearchMatch.text("Kindness in a translation", query: "kindness")
        #expect(SearchMatch.visibleBlocks([otherMatch, note], preferred: 0) == [0, 1])
        #expect(SearchMatch.visibleBlocks([excerpt, AttributedString("Translation")], preferred: 1) == [1])
        #expect(SearchMatch.visibleBlocks([excerpt, AttributedString()], preferred: 1) == [0])
        #expect(SearchMatch.visibleBlocks([AttributedString(), AttributedString()], preferred: 0).isEmpty)
    }

    @Test func referenceAndSemanticFallbackStartAtBeginning() {
        let text = SearchMatch.text("Opening words and remaining text", query: "2:255")
        #expect(String(SearchMatch.preview(text, compact: true).characters) == "Opening words and remaining text")
    }
}
