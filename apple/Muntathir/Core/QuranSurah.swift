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

enum QuranSearchText {
    /// Search keys only. Never apply this to displayed or shared Quran text.
    static func normalize(_ text: String) -> String {
        String(text.unicodeScalars.compactMap { scalar -> String? in
            switch scalar.value {
            case 0x0610 ... 0x061A, 0x0640, 0x064B ... 0x065F, 0x0670, 0x06D6 ... 0x06ED:
                nil
            case 0x0622, 0x0623, 0x0625, 0x0671: "ا"
            default: String(scalar)
            }
        }.joined())
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

    static func expression(_ text: String) -> String? {
        let terms = text.split { character in
            !character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) }
        }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"" }.joined(separator: " AND ")
    }
}
