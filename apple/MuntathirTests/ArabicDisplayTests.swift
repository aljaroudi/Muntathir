@testable import Muntathir
import Testing
import UIKit

struct ArabicDisplayTests {
    @Test func selectionAndStyleSurviveHiddenMarks() {
        let prefix = "🌙 أ آ أ آ ۖ "
        let word = "رَّحۡمَٰنࣰ"
        let original = NSMutableAttributedString(string: prefix + word)
        let sourceRange = NSRange(location: prefix.utf16.count, length: word.utf16.count)
        original.addAttribute(.underlineStyle, value: 1, range: sourceRange)
        let display = ArabicDisplay(original, showMarks: false)
        let visible = NSRange(location: prefix.utf16.count, length: 4)
        #expect(Array(display.attributed.string.utf16) == Array((prefix + "رحمن").utf16))
        #expect(display.displayRange(sourceRange) == visible)
        let saved = HighlightRange(display.sourceRange(visible), in: original.string)
        #expect(saved?.quote == word)
        #expect(saved?.validated(in: original.string) == sourceRange)
        #expect(display.attributed.attribute(.underlineStyle, at: visible.location, effectiveRange: nil) != nil)
        #expect(ArabicDisplay(original, showMarks: true).attributed.string == prefix + word)
    }
}
