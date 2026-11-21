import Foundation

struct HadithIntroduction: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let arabic: String
    let english: String
    let bookArabic: String
    let bookEnglish: String
    var bookID = ""

    var readingWords = 0

    /// Highlights key on the book, which stays stable when the database is rebuilt.
    var highlightSource: String {
        Self.highlightPrefix + bookID
    }

    static let highlightPrefix = "introduction:"

    var highlightBlocks: [String: String] {
        ["arabic": HighlightTextContent.canonical(HadithText.markdown(arabic)),
         "english": HighlightTextContent.canonical(HadithText.markdown(english))]
    }

    func bookTitle(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" || bookEnglish.isEmpty ? bookArabic : bookEnglish
    }
}
