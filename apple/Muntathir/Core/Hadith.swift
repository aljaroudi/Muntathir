import Foundation

struct HadithCollection: Identifiable, Hashable, Sendable {
    let id: String
    let arabic: String
    let english: String
    let count: Int

    var group: HadithBookGroup {
        .init(collectionID: id)
    }

    func title(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" || english.isEmpty ? arabic : english
    }

    func matches(_ query: String) -> Bool {
        let terms = QuranSearchText.terms(query)
        let text = QuranSearchText.normalize(arabic + " " + english).lowercased()
        return !terms.isEmpty && terms.allSatisfy { text.contains($0) }
    }
}

struct HadithChapter: Identifiable, Hashable, Sendable {
    let id: Int
    let arabic: String
    let english: String
    let bookArabic: String
    let bookEnglish: String

    func title(locale: Locale) -> String {
        let book = bookTitle(locale: locale)
        let chapter = chapterTitle(locale: locale)
        return chapter.isEmpty ? book : book + " · " + chapter
    }

    func bookTitle(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" || bookEnglish.isEmpty ? bookArabic : bookEnglish
    }

    func chapterTitle(locale: Locale) -> String {
        (locale.language.languageCode?.identifier == "ar" && !arabic.isEmpty) || english.isEmpty ? arabic : english
    }
}

/// Preview text is prepared one result at a time; pages never retain complete narration text.
struct Hadith: Identifiable, Hashable, Sendable {
    let id: Int
    let collectionID: String
    let number: Int
    let chapter: HadithChapter
    let arabic: String
    let englishNarrator: String
    let english: String
    var source: HadithSource?
    var arabicDisplay: AttributedString = .init()
    var englishDisplay: AttributedString = .init()
    var narratorDisplay: AttributedString = .init()
}

struct HadithPage: Sendable {
    let rows: [Hadith]
    let hasMore: Bool
    var usedOrderedFallback = false
    var nextCursor: HadithCursor?
}

struct HadithDetail: Sendable {
    let narration: Hadith
    let author: String
    let authorArabic: String

    func authorName(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" && !authorArabic.isEmpty ? authorArabic : author
    }

    let gradings: [HadithGrading]
    let previousID: Int?
    let nextID: Int?
}

struct HadithRequest: Codable, Equatable, Sendable {
    var query = ""
    var collectionID: String?
    var chapterID: Int?
    var number: Int?
    var cursor = HadithCursor()
}

struct HadithGrading: Identifiable, Hashable, Sendable {
    let id: Int
    let graderID: String?
    let graderArabic: String
    let graderEnglish: String
    let gradeArabic: String
    let gradeEnglish: String
    let referenceArabic: String
    let referenceEnglish: String
    let status: String
    let originalText: String

    func grader(locale: Locale) -> String {
        localized(arabic: graderArabic, english: graderEnglish, locale: locale)
    }

    func judgment(locale: Locale) -> String {
        localized(arabic: gradeArabic, english: gradeEnglish, locale: locale)
    }

    func reference(locale: Locale) -> String {
        localized(arabic: referenceArabic, english: referenceEnglish, locale: locale)
    }

    private func localized(arabic: String, english: String, locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "ar" {
            arabic.isEmpty ? english : arabic
        } else {
            english.isEmpty ? arabic : english
        }
    }
}

enum HadithBookGroup: CaseIterable, Identifiable {
    case four, six, other

    var title: LocalizedStringResource {
        switch self {
        case .four: "The Four"
        case .six: "The Six"
        case .other: "Other books"
        }
    }

    var id: Self {
        self
    }

    init(collectionID: String) {
        self = switch collectionID {
        case "bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah":
            .six
        case "alkafi", "additional-Man-La-Yahduruh-al-Faqih-Saduq",
             "additional-Tahdhib-al-Ahkam-Tusi", "additional-Al-Istibsar-Tusi":
            .four
        default:
            .other
        }
    }
}

struct HadithCursor: Codable, Equatable, Sendable {
    enum Phase: Int, Codable, Sendable { case words, substring }
    var phase: Phase = .words
    var afterID = 0
}

/// Source identity survives generated SQLite row renumbering.
struct HadithSource: Codable, Hashable, Sendable {
    let book: String
    let chapterFile: String
    let number: Int
    let sourceID: Int?

    var key: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self).base64EncodedString()) ?? ""
    }

    init(book: String, chapterFile: String, number: Int, sourceID: Int?) {
        self.book = book; self.chapterFile = chapterFile; self.number = number; self.sourceID = sourceID
    }

    init?(key: String) {
        guard let data = Data(base64Encoded: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }
}
