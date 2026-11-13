@testable import Muntathir
import SwiftUI
import Testing

struct SearchPreviewTests {
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
