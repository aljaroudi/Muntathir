import Foundation
@testable import Muntathir
import SwiftUI
import Testing

struct HadithTextTests {
    @Test func markdownPreservesParagraphsHeadingsListsAndLinks() {
        let text = HadithText.markdown("# Heading\n\nA **bold** and *italic* [link](https://example.com).\n\n- one\n- two\n\n> quote")
        let paragraphs = HadithText.paragraphs(text)
        #expect(paragraphs.count == 5)
        #expect(paragraphs[0].heading == 1)
        #expect(paragraphs[2].marker == "•")
        #expect(paragraphs[4].quoted)
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(text.runs.contains { $0.link?.absoluteString == "https://example.com" })
        #expect(String(HadithText.flattened(text).characters).contains("Heading\nA bold"))
    }

    @Test func arabicPreviewCentersLateMatchesAndKeepsDiacritics() {
        let source = String(repeating: "مقدمة طويلة ", count: 100) + "**إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ**" + String(repeating: " خاتمة", count: 100)
        let preview = HadithText.preview(source, terms: QuranSearchText.terms("الاعمال"))
        let plain = String(preview.characters)
        #expect(plain.hasPrefix("… "))
        #expect(plain.contains("الأَعْمَالُ"))
        #expect(plain.count <= 264)
        #expect(!plain.contains("**"))
        let matches = preview.runs.filter { $0.underlineStyle != nil }.map { String(preview[$0.range].characters) }.joined()
        #expect(matches == "الأَعْمَالُ")
    }

    @Test func markedEnglishPreviewPreservesMarkdownAndStemSpans() {
        let source = String(repeating: "Some introduction. ", count: 100) + "**\(HadithText.startMarker)believers\(HadithText.endMarker)** have [faith](https://example.com)."
        let preview = HadithText.preview(source, marked: true)
        #expect(String(preview.characters).contains("believers"))
        #expect(!String(preview.characters).contains(HadithText.startMarker))
        #expect(preview.runs.contains { $0.underlineStyle != nil && $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(preview.runs.contains { $0.link != nil })
    }

    @Test func fullHighlightsKeepMarkdownAndNeverTruncate() {
        let source = "# Heading\n\n" + String(repeating: "مقدمة طويلة ", count: 100) + "**الأَعْمَالُ**\n\n- خاتمة"
        let full = HadithText.highlighted(source, terms: QuranSearchText.terms("الاعمال"))
        #expect(full.characters.count > 1000)
        #expect(HadithText.paragraphs(full).first?.heading == 1)
        #expect(HadithText.paragraphs(full).last?.marker == "•")
        #expect(full.runs.contains { $0.underlineStyle != nil })
        let marked = "\(HadithText.startMarker)narrator books\(HadithText.endMarker) end"
        let narrator = HadithText.highlighted(HadithText.markedSlice(marked, range: 0 ..< 8), marked: true)
        let body = HadithText.highlighted(HadithText.markedSlice(marked, range: 9 ..< 18), marked: true)
        #expect(String(narrator.characters) == "narrator")
        #expect(String(body.characters) == "books end")
        #expect(narrator.runs.contains { $0.underlineStyle != nil })
        #expect(body.runs.contains { $0.underlineStyle != nil })
    }

    @Test func quranPreviewCentersLiteralMatchWithoutParsingOrChangingSource() {
        let source = String(repeating: "مقدمة طويلة ", count: 40) + "كُرْسِيُّهُ" + String(repeating: " خاتمة", count: 40)
        let preview = SearchMatch.preview(SearchMatch.text(source, query: "كرسي"))
        #expect(String(preview.characters).hasPrefix("… "))
        #expect(String(preview.characters).contains("كُرْسِيُّهُ"))
        #expect(preview.runs.contains { $0.underlineStyle != nil })
        #expect(SearchMatch.text("**نص**", query: "نص").characters.count == 6)
    }

    @Test func previewBoundsAndUnmatchedTextAreSafe() {
        #expect(HadithText.preview("").characters.isEmpty)
        let snippet = HadithText.preview("**Hello**\n\nworld", terms: ["absent"])
        #expect(String(snippet.characters) == "Hello\nworld")
        #expect(snippet.runs.allSatisfy { $0.underlineStyle == nil })
        let multi = HadithText.preview("رحمة ورحمة", terms: ["رحمه"])
        #expect(multi.runs.filter { $0.underlineStyle != nil }.count == 2)
    }
}
