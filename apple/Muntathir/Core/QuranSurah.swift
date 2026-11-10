import Foundation

struct QuranSurah: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let arabic: String
    let transliteration: String

    static func load(bundle: Bundle = .main) throws -> [QuranSurah] {
        guard let url = bundle.url(forResource: "quran-surahs", withExtension: "json") else { throw QuranDatabaseError.unavailable }
        let surahs = try JSONDecoder().decode([QuranSurah].self, from: Data(contentsOf: url))
        guard surahs.map(\.id) == Array(1 ... 114) else { throw QuranDatabaseError.unavailable }
        return surahs
    }

    func title(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" ? arabic : transliteration
    }

    func matches(_ query: String) -> Bool {
        if let number = QuranSearchText.number(query) {
            return id == number
        }
        let normalized = QuranSearchText.normalize(query).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        return QuranSearchText.normalize(arabic).contains(normalized)
            || (!nameKey(query).isEmpty && nameKey(transliteration).contains(nameKey(query)))
    }

    private func nameKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .filter(\.isLetter)
            .replacingOccurrences(of: "aa", with: "a")
            .replacingOccurrences(of: "ii", with: "i")
            .replacingOccurrences(of: "uu", with: "u")
    }
}

/// Display only: source IDs and stored references remain chapter:verse.
enum QuranReference {
    private static let names = Dictionary(uniqueKeysWithValues: ((try? QuranSurah.load()) ?? []).map { ($0.id, $0.arabic) })

    static func display(_ reference: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "ar",
              let parsed = try? QuranSearchText.reference(reference),
              let name = names[parsed.surah] else { return reference }
        // Isolate the numeric run so RTL surroundings cannot reverse chapter and verse.
        return name + " " + "\u{2066}" + reference + "\u{2069}"
    }
}

enum QuranSearchText {
    /// Search keys only. Never apply this to displayed or shared Quran text.
    /// Must match the normalization the bundled search indexes were built with.
    static func normalize(_ text: String) -> String {
        guard !text.utf8.allSatisfy({ $0 < 128 }) else { return text }
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0610 ... 0x061A, 0x0640, 0x064B ... 0x065F, 0x0670, 0x06D6 ... 0x06ED:
                continue
            case 0x0622, 0x0623, 0x0625, 0x0671: result.append("ا")
            case 0x0649: result.append("ي")
            case 0x0629: result.append("ه")
            default: result.append(scalar)
            }
        }
        return String(result)
    }

    static func number(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.wholeNumberValue != nil }) else { return nil }
        return Int(trimmed.compactMap { $0.wholeNumberValue.map(String.init) }.joined())
    }

    static func reference(_ text: String) throws -> (surah: Int, verse: Int)? {
        guard text.contains(":"), text.trimmingCharacters(in: .whitespacesAndNewlines).first?.wholeNumberValue != nil else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let surah = number(String(parts[0])), let verse = number(String(parts[1])),
              (1 ... 114).contains(surah), verse > 0 else { throw QuranDatabaseError.invalidReference }
        return (surah, verse)
    }

    /// Normalized, lowercased words of a query; never contains FTS syntax characters.
    static func terms(_ text: String) -> [String] {
        normalize(text).lowercased().split { character in
            !character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) }
        }.map(String.init)
    }

    /// 0: literal whole words, 1: literal substrings, 2: broader index matches.
    /// Phrase matching is used by Hadith; Quran retains its all-terms semantics.
    static func literalRank(_ text: String, terms: [String], phrase: Bool = false) -> Int {
        let terms = terms.map { $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en")) }
        guard !terms.isEmpty else { return 2 }
        // A single word only needs occurrence boundaries, not tokenization of the whole narration.
        if terms.count == 1 {
            let source = normalize(text).lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
            var start = source.startIndex
            var rank = 2
            func wordCharacter(_ character: Character) -> Bool {
                character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) }
            }
            while start < source.endIndex, let range = source.range(of: terms[0], range: start ..< source.endIndex) {
                let beginsWord = range.lowerBound == source.startIndex || !wordCharacter(source[source.index(before: range.lowerBound)])
                let endsWord = range.upperBound == source.endIndex || !wordCharacter(source[range.upperBound])
                if beginsWord, endsWord {
                    return 0
                }
                rank = 1
                start = source.index(after: range.lowerBound)
            }
            return rank
        }
        let words = Self.terms(text).map { $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en")) }
        if phrase {
            guard words.count >= terms.count else { return 2 }
            var rank = 2
            for start in 0 ... words.count - terms.count {
                let pairs = zip(words[start ..< start + terms.count], terms)
                if pairs.allSatisfy({ $0 == $1 }) {
                    return 0
                }
                if pairs.allSatisfy({ $0.contains($1) }) {
                    rank = 1
                }
            }
            return rank
        }
        let wholeWords = Set(words)
        if terms.allSatisfy(wholeWords.contains) {
            return 0
        }
        return terms.allSatisfy { term in words.contains { $0.contains(term) } } ? 1 : 2
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0 ... b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
