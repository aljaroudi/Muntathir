import Foundation

enum MachineTranslation {
    /// The language to machine-translate `source` into: the reader's top preferred language,
    /// or nil when the reader already reads the source (it is one of their preferred languages).
    static func target(from source: Locale.Language, preferred: [String] = Locale.preferredLanguages) -> Locale.Language? {
        let codes = preferred.compactMap { Locale(identifier: $0).language.languageCode }
        guard let top = preferred.first, let sourceCode = source.languageCode, !codes.contains(sourceCode) else { return nil }
        return Locale(identifier: top).language
    }

    /// Splits text into paragraphs so each translation request stays short and structure survives.
    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
