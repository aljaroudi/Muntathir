import Foundation
@testable import Muntathir
import Testing

struct DictionarySummarizerTests {
    private func definition(_ source: Int, _ body: String) -> DictionaryReader.Definition {
        DictionaryReader.Definition(id: Int64(source), source: source, root: "كتب", body: body)
    }

    @Test func passagesPreferConciseDictionaries() {
        let definitions = [definition(4, "لسان."), definition(0, "قاموس."), definition(2, "صحاح.")]
        let passages = DictionarySummarizer.passages(definitions, budget: 1000)
        #expect(passages.map(\.source) == [0, 2, 4])
        #expect(passages.map(\.text) == ["قاموس.", "صحاح.", "لسان."])
    }

    @Test func passagesSplitAtSentencesAndLines() {
        let passages = DictionarySummarizer.passages([definition(0, "الكتاب معروف. والجمع كتب\nوكتب الشيء خطه؟ ")], budget: 1000)
        #expect(passages.map(\.text) == ["الكتاب معروف.", "والجمع كتب", "وكتب الشيء خطه؟"])
    }

    @Test func passagesSkipSentencesThatDoNotFit() {
        let long = String(repeating: "ل", count: 50) + "."
        let passages = DictionarySummarizer.passages([definition(0, "قصير. \(long) آخر.")], budget: 20)
        #expect(passages.map(\.text) == ["قصير.", "آخر."])
    }

    @Test func passagesOfNothingAreEmpty() {
        #expect(DictionarySummarizer.passages([], budget: 1000).isEmpty)
    }
}
