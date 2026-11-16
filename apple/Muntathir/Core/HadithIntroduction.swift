import Foundation

struct HadithIntroduction: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let arabic: String
    let english: String
    let bookArabic: String
    let bookEnglish: String

    var readingWords = 0

    func bookTitle(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" || bookEnglish.isEmpty ? bookArabic : bookEnglish
    }
}
