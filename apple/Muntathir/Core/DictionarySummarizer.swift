import Foundation
import FoundationModels
import OSLog

/// Picks the sentences of a root's definitions that state its core meanings. The model answers with
/// sentence numbers, so passages are always the dictionaries' own text.
actor DictionarySummarizer {
    static let shared = DictionarySummarizer()

    struct Passage: Sendable, Equatable {
        var text: String
        var source: Int
    }

    /// Concise dictionaries first; لسان العرب mostly repeats the others.
    private static let priority = [0, 2, 3, 1, 5, 4]
    /// Characters per request; the second is a retry when Arabic overflows the context.
    private static let budgets = [6000, 3500]
    private static let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "DictionarySummarizer")
    private var cache: [String: [Passage]] = [:]

    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Reports passages as they stream in; nil when the model can't summarize.
    func summarize(root: String, definitions: [DictionaryReader.Definition], revision: Int,
                   update: @Sendable ([Passage]) async -> Void) async -> [Passage]?
    {
        let key = "\(root)|\(revision)"
        if let cached = cache[key] {
            return cached
        }
        for budget in Self.budgets {
            let passages = Self.passages(definitions, budget: budget)
            guard Self.isAvailable, !passages.isEmpty else { return nil }
            let numbered = passages.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
            You read numbered sentences from classical Arabic dictionary entries for one root. Choose the \
            sentences that best state the root's core meanings, skipping repeats, poetry, chains of \
            narrators, and grammatical debates.
            """)
            do {
                let stream = session.streamResponse(to: "Root: \(root)\n\n\(numbered)", generating: Choice.self,
                                                    options: GenerationOptions(samplingMode: .greedy))
                for try await snapshot in stream {
                    await update(Self.chosen(snapshot.content.sentences ?? [], from: passages))
                }
                let chosen = try await Self.chosen(stream.collect().content.sentences, from: passages)
                guard !chosen.isEmpty else { return nil }
                cache[key] = chosen
                return chosen
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                continue
            } catch {
                if !(error is CancellationError) {
                    Self.log.error("Summarizing \(root, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
                return nil
            }
        }
        return nil
    }

    /// Sentences in `priority` order up to `budget` characters, skipping any that don't fit.
    nonisolated static func passages(_ definitions: [DictionaryReader.Definition], budget: Int) -> [Passage] {
        var passages: [Passage] = []
        var used = 0
        for definition in priority.flatMap({ source in definitions.filter { $0.source == source } }) {
            for line in definition.body.split(whereSeparator: \.isNewline) {
                for match in line.matches(of: /[^.؟!]+[.؟!]*/) {
                    let sentence = match.output.trimmingCharacters(in: .whitespaces)
                    guard !sentence.isEmpty, used + sentence.count <= budget else { continue }
                    passages.append(Passage(text: sentence, source: definition.source))
                    used += sentence.count
                }
            }
        }
        return passages
    }

    /// Chosen sentences in text order, ignoring repeated or invalid numbers.
    private nonisolated static func chosen(_ numbers: [Int], from passages: [Passage]) -> [Passage] {
        Set(numbers).filter { passages.indices.contains($0 - 1) }.sorted().map { passages[$0 - 1] }
    }

    @Generable
    struct Choice {
        @Guide(description: "Numbers of the sentences that state the root's core meanings", .count(1 ... 6))
        var sentences: [Int]
    }
}
