import Foundation
import Translation

enum MachineTranslation {
    /// The target for `source` only when Apple Translation supports the pair. Supported but
    /// not-yet-downloaded languages count: the translation task asks the reader to download them.
    static func supportedTarget(from source: Locale.Language, preferred: [String] = Locale.preferredLanguages) async -> Locale.Language? {
        guard let target = target(from: source, preferred: preferred) else { return nil }
        return await LanguageAvailability().status(from: source, to: target) == .unsupported ? nil : target
    }

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
