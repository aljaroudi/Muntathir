import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import UIKit

@MainActor struct HighlightTextTests {
    @Test func searchUnderlinesCoexistWithSavedColorsAndKeepSourceText() {
        let raw = "رَحْمَةٌ ورحمة — mercy mercy"
        let query = "رحمة mercy"
        let ranges = SearchMatch.ranges(in: raw, terms: QuranSearchText.terms(query))
        #expect(ranges.count == 4)
        #expect((raw as NSString).substring(with: ranges[0]) == "رَحْمَةٌ")
        let highlighted = SearchMatch.applying(to: NSMutableAttributedString(string: raw), query: query)
        let saved = ReadingHighlight(source: "1:1", isHadith: false, excerpt: raw, reference: "1:1", color: .yellow)
        let rendered = HighlightTextContent.applying([saved], to: highlighted, block: "arabic")
        #expect(rendered.string == raw)
        for range in ranges {
            #expect(rendered.attribute(.underlineStyle, at: range.location, effectiveRange: nil) != nil)
            #expect(rendered.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil)
        }
        #expect(SearchMatch.ranges(in: raw, terms: ["unrelated"]).isEmpty)
        let plain = SearchMatch.applying(to: NSMutableAttributedString(string: raw), query: "")
        #expect(plain.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test func nativeSelectionSurvivesRenderingAndHighlightUpdates() throws {
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"))
        let content = try QuranPageText(page: database.page(2), surahs: QuranSurah.load())
        let rendered = QuranPageReader.attributed(content, width: 320, lineHeight: 36)
        let view = HighlightUITextView()
        view.isEditable = false
        view.setRenderedText(rendered)
        let word = try #require(content.words.first { $0.canonical != nil })
        view.selectedRange = word.display
        view.setRenderedText(rendered)
        #expect(view.selectedRange == word.display)
        let colored = NSMutableAttributedString(attributedString: rendered)
        colored.addAttribute(.backgroundColor, value: UIColor.yellow, range: word.display)
        view.setRenderedText(colored)
        #expect(view.selectedRange == word.display)
    }

    @Test func mushafLayoutFitsSmallPhoneAndTabletWithoutClipping() throws {
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"))
        let surahs = try QuranSurah.load()
        for page in [1, 2, 42, 187, 604] {
            let content = try QuranPageText(page: database.page(page), surahs: surahs)
            for (width, height) in [(320.0, 520.0), (744.0, 900.0)] {
                let lineHeight = height / 15
                let view = UITextView()
                view.textContainerInset = .zero
                view.textContainer.lineFragmentPadding = 0
                view.isScrollEnabled = false
                view.attributedText = QuranPageReader.attributed(content, width: width, lineHeight: lineHeight)
                let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                #expect(fitted.height <= lineHeight * Double(content.lines.count) + 1, "Page \(page), width \(width): \(fitted.height)")
            }
        }
    }

    @Test func mushafHighlightColorsIncludeInterwordWhitespace() throws {
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"))
        let content = try QuranPageText(page: database.page(1), surahs: [])
        let words = content.words.filter { $0.source == "1:1" && $0.canonical != nil }
        let value = try #require(content.highlights(in: [NSUnionRange(words[0].display, words[1].display)]).first)
        let rendered = HighlightTextContent.applying([value], to: NSAttributedString(string: content.text), block: "arabic", mappedRanges: [value.id: content.displayRanges(for: value)])
        #expect(rendered.attribute(.backgroundColor, at: NSMaxRange(words[0].display), effectiveRange: nil) != nil)
        #expect(rendered.attribute(.backgroundColor, at: words[2].display.location, effectiveRange: nil) == nil)
    }

    @Test func newestColorWinsOverlapWithoutChangingTextOrNotes() throws {
        let text = "one two three"
        var first = ReadingHighlight(source: "1:1", isHadith: false, excerpt: text, reference: "1:1", color: .yellow, note: "First")
        first.modifiedAt = Date(timeIntervalSince1970: 1)
        var second = try ReadingHighlight(source: "1:1", isHadith: false, block: "arabic",
                                          ranges: [#require(HighlightRange(NSRange(location: 4, length: 3), in: text))], excerpt: "two", reference: "1:1", color: .blue, note: "Second")
        second.modifiedAt = Date(timeIntervalSince1970: 2)
        let rendered = HighlightTextContent.applying([second, first], to: NSAttributedString(string: text), block: "arabic", differentiate: true)
        #expect(rendered.string == text)
        #expect(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor == UIColor(Color.yellow).withAlphaComponent(0.3))
        #expect(rendered.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? UIColor == UIColor(Color.blue).withAlphaComponent(0.3))
        #expect(rendered.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(first.note == "First" && second.note == "Second")
        let translation = HighlightTextContent.applying([second], to: NSAttributedString(string: text), block: "en.qarai")
        #expect(translation.attribute(.backgroundColor, at: 4, effectiveRange: nil) == nil)
    }

    @Test func formattedHadithSelectionsCrossParagraphsAndPreserveFormatting() throws {
        let markdown = HadithText.markdown("# Heading\n\nFirst **bold** paragraph.\n\n> Second paragraph.\n\n- List item")
        let text = HighlightTextContent.canonical(markdown)
        let attributed = HighlightTextContent.attributed(text: text, markdown: markdown, arabic: false, size: 17, alignment: .natural)
        #expect(attributed.string == text)
        #expect(text.contains("│ Second paragraph."))
        #expect(text.contains("• List item"))
        let bold = (text as NSString).range(of: "bold")
        let font = try #require(attributed.attribute(.font, at: bold.location, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        let start = (text as NSString).range(of: "paragraph.").location
        let end = (text as NSString).range(of: "Second").location + 6
        let selected = try #require(HighlightRange(NSRange(location: start, length: end - start), in: text))
        #expect(selected.quote.contains("\n\n"))
        #expect(selected.validated(in: attributed.string) != nil)
    }
}
