import Foundation
import FoundationModels

/// Last resort when dictionary lookup finds no root for a word: the on-device model picks one of
/// the headings the word could come from (`DictionaryReader.candidateRoots`), or none. Guided
/// generation restricts it to those choices, so a suggestion is always a real heading whose
/// letters the word contains; the dictionary view labels it as inferred.
actor DictionaryRootSuggester {
    static let shared = DictionaryRootSuggester()
    private static let none = "none"
    private var cache: [String: String?] = [:]

    nonisolated static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.supportsLocale(Locale(identifier: "ar"))
    }

    func suggest(for word: String, candidates: [String]) async -> String? {
        if let cached = cache[word] {
            return cached
        }
        guard Self.isAvailable, !candidates.isEmpty else { return nil }
        let root: String?
        do {
            let schema = try GenerationSchema(root: DynamicGenerationSchema(
                name: "Root", description: "The word's Arabic root as classical dictionaries file it, or none", anyOf: candidates + [Self.none]
            ),
            dependencies: [])
            let session = LanguageModelSession(instructions: """
            You identify the root (الجذر) of a classical Arabic word, as Lisan al-Arab files it. \
            Strip prefixes such as و ف ب ل ك س ال and suffixes such as pronouns and plural endings, then \
            restore any weak letter the form drops. Choose only from the allowed roots. Choose none for \
            particles, pronouns, and personal or place names, or when no allowed root fits.
            Examples: المستغفرين → غفر; فتوضأ → وضأ; يقولون → قول; وعدتم → وعد; محمد → none; لكنه → none.
            """)
            let response = try await session.respond(to: "Word: \(word)", schema: schema, options: GenerationOptions(samplingMode: .greedy))
            let choice = try response.content.value(String.self)
            root = choice == Self.none || !candidates.contains(choice) ? nil : choice
        } catch {
            // Unavailable model, unsupported language, or guardrails: show nothing rather than a guess.
            return nil
        }
        cache[word] = root
        return root
    }
}
