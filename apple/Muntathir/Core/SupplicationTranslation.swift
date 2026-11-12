import Foundation

struct SupplicationTranslation: Identifiable, Hashable, Sendable {
    let language: String
    let edition: String
    let text: String
    var id: String {
        language + ":" + edition
    }

    var block: String {
        "translation:" + id
    }

    var isRightToLeft: Bool {
        Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    static func selected(from translations: [Self], selection: String, languages: [String]) -> Self? {
        guard selection != "none" else { return nil }
        if selection != "auto" {
            return translations.first { $0.id == selection || $0.language == selection }
        }
        for language in languages {
            let code = Locale(identifier: language).language.languageCode?.identifier
            if code == "ar" {
                return nil
            }
            if let match = translations.first(where: { Locale(identifier: $0.language).language.languageCode?.identifier == code }) {
                return match
            }
        }
        return nil
    }
}
