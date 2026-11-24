import Foundation
@testable import Muntathir
import Testing

struct QuranSpellingTests {
    private struct Fixture: Decodable {
        struct Fold: Decodable {
            let text: String
            let key: String
        }

        struct Term: Decodable {
            let term: String
            let docs: Int
        }

        struct Case: Decodable {
            let typed: String
            let prefix: Bool
            let resolved: String
        }

        struct Candidates: Decodable {
            let key: String
            let spellings: [String: Int]
        }

        let fold: [Fold]
        let vocabulary: [Term]
        let cases: [Case]
        let candidates: [Candidates]
    }

    private static func fixture() throws -> Fixture {
        let url = try #require(Bundle(for: SpellingFixtures.self).url(forResource: "quran-spelling", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func resolvesLikeTheReferenceImplementation() throws {
        let fixture = try Self.fixture()
        #expect(fixture.cases.count > 40)
        let vocabulary = QuranVocabulary(fixture.vocabulary.map { ($0.term, $0.docs) })
        for item in fixture.fold {
            #expect(QuranSearchText.normalize(item.text) == item.key, "\(item.text)")
        }
        for item in fixture.cases {
            let key = QuranSearchText.normalize(item.typed)
            #expect(QuranSpelling.resolve(key, in: vocabulary, prefix: item.prefix) == item.resolved, "\(item.typed)")
        }
        for item in fixture.candidates {
            #expect(QuranSpelling.candidates(item.key) == item.spellings, "\(item.key)")
        }
    }

    @Test func highlightsTheMushafsSpellingOfATypedWord() {
        let verse = "وَأَقِيمُوا۟ ٱلصَّلَوٰةَ وَءَاتُوا۟ ٱلزَّكَوٰةَ"
        func marked(_ query: String) -> [String] {
            SearchMatch.ranges(in: verse, terms: QuranSearchText.queryTerms(query)).map { (verse as NSString).substring(with: $0) }
        }
        #expect(marked("الصلاة") == ["ٱلصَّلَوٰةَ"])
        #expect(marked("الزكاة") == ["ٱلزَّكَوٰةَ"])
        #expect(SearchMatch.ranges(in: "ٱلرَّحْمَٰنِ عَلَّمَ ٱلْقُرْءَانَ", terms: QuranSearchText.queryTerms("القران")).count == 1)
        // A spelling that already occurs is used as typed, and unrelated words are not marked.
        #expect(marked("الصلوة") == ["ٱلصَّلَوٰةَ"])
        #expect(marked("الكتاب").isEmpty)
    }

    @Test func termsResolveAsPrefixOnlyAtTheEnd() {
        let vocabulary = QuranVocabulary([("الصلوه", 55), ("ءامنوا", 254), ("الصلب", 2)])
        #expect(QuranSpelling.resolve(["امنوا", "الصلا"], in: vocabulary) == ["ءامنوا", "الصلو"])
        // Non-Arabic terms and words the index lacks stay as typed.
        #expect(QuranSpelling.resolve(["mercy", "كمبيوتر"], in: vocabulary) == ["mercy", "كمبيوتر"])
    }
}

private final class SpellingFixtures: NSObject {}
