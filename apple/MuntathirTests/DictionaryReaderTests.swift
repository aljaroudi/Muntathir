import Foundation
@testable import Muntathir
import Testing

struct DictionaryReaderTests {
    private struct Normalization: Decodable {
        struct Word: Decodable {
            let text: String
            let spell: String
            let normalize: String
        }

        let words: [Word]
    }

    /// The pack built by shared/lexicon/build.py, when this checkout has one.
    private static let pack = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/Lexicon/lexicon.db")

    @Test func spellingMatchesTheLexiconBuild() throws {
        let url = try #require(Bundle(for: DictionaryFixtures.self).url(forResource: "lexicon-normalize", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Normalization.self, from: Data(contentsOf: url))
        #expect(fixture.words.count > 20)
        for word in fixture.words {
            #expect(DictionaryReader.spell(word.text) == word.spell, "\(word.text)")
            #expect(DictionaryReader.normalize(word.text) == word.normalize, "\(word.text)")
        }
    }

    @Test func stemsFollowCliticGrammar() {
        #expect(DictionaryReader.stems(of: "والكتاب") == ["الكتاب", "كتاب"])
        #expect(DictionaryReader.stems(of: "للذين").first == "الذين")
        #expect(DictionaryReader.stems(of: "بأصحابه").contains("أصحاب"))
        // The article takes no pronoun, and stems keep three letters.
        #expect(!DictionaryReader.stems(of: "الكتابه").contains("الكتاب"))
        #expect(DictionaryReader.stems(of: "وله").isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: pack.path)))
    func selectionsResolveToTheirRoots() async throws {
        let reader = DictionaryReader()
        try await reader.install(Self.pack)
        for (word, root) in [("الصَّلاةُ", "صلو"), ("السَّمَٰوَٰتِ", "سمو"), ("فَسَيَكْفِيكَهُمُ", "كفي"), ("الحق", "حقق"),
                             ("كنت", "كون"), ("حدثنا", "حدث"), ("يجب", "وجب"), ("بالمؤمنين،", "أمن")]
        {
            #expect(try await reader.search(word).first == root, "\(word)")
        }
        // A word the Quran corpus verifies has only its verified root (1:4 مَٰلِكِ once also listed أول).
        #expect(try await reader.search("مَٰلِكِ") == ["ملك"])
        #expect(try await reader.search("مالك") == ["ملك"])
        #expect(try await reader.search("فرحين") == ["فرح"])
        // Particles have no root, and a phrase is looked up one word at a time.
        #expect(try await reader.search("الذين").isEmpty)
        #expect(try await reader.search("قال رسول الله").isEmpty)
        // Every source's definition shows, whichever spelling of the root it files it under.
        let definitions = try await reader.entry("سما")
        #expect(Set(definitions.map(\.source)) == Set(0 ..< 6))
        #expect(definitions.contains { $0.root == "سمو" })
        let candidates = try await reader.candidateRoots(for: "المستغفرين")
        #expect(candidates.contains("غفر"))
        #expect(!candidates.contains("كتب"))
    }
}

private final class DictionaryFixtures: NSObject {}
