@testable import Muntathir
import Testing

struct SearchRelevanceTests {
    @Test func exactAndProximityPrecedeBroaderMatches() throws {
        let terms = QuranSearchText.terms("acts mercy")
        let exact = try #require(SearchRelevance.score("acts mercy", terms: terms))
        let near = try #require(SearchRelevance.score("acts of mercy", terms: terms))
        let far = try #require(SearchRelevance.score("acts described in many other words before mercy", terms: terms))
        #expect(exact < near)
        #expect(near < far)
        #expect(SearchRelevance.score("mercy", terms: terms) == nil)
    }

    @Test func conservativeCorrections() {
        #expect(SearchRelevance.score("intentions", terms: ["intentinos"])?.tier == 2)
        #expect(SearchRelevance.score("cat", terms: ["bat"]) == nil)
        #expect(SearchRelevance.score("acts of mercy", terms: ["acts", "mercy", "parents"])?.tier == 2)
        #expect(SearchRelevance.score("mercy", terms: ["acts", "mercy", "parents"]) == nil)
    }

    @Test func arabicNormalizationPreservesExactPriority() {
        #expect(SearchRelevance.score("إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", terms: QuranSearchText.terms("انما الاعمال بالنيات"))?.tier == 0)
    }
}

extension SearchRelevanceTests {
    @Test func numericReferencesMatchArabicOnlyText() {
        #expect(SearchRelevance.score("1:1 بِسْمِ اللَّهِ", terms: QuranSearchText.terms("1:1"))?.tier == 0)
        #expect(SearchRelevance.score("1:1 بِسْمِ اللَّهِ", terms: ["mercy"]) == nil)
    }
}
