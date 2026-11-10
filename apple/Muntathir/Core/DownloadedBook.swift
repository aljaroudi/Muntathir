import Foundation

struct DownloadedBook: Identifiable, Sendable {
    let id: String
    let arabic: String
    let english: String
    let installed: Bool

    func title(locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ar" || english.isEmpty ? arabic : english
    }
}
