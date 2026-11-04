import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import UIKit

@MainActor struct HighlightTextTests {
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
