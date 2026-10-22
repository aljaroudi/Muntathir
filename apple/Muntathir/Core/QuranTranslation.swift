import Foundation

/// Each translation is bundled as `<id>.db` next to the Arabic `quran.db`.
struct QuranTranslation: Identifiable, Hashable, Sendable {
    let language: String
    let translator: String
    let id: String

    static let catalog: [QuranTranslation] = [
        .init(language: "zh", translator: "马坚", id: "zh.jian"),
        .init(language: "zh-Hant", translator: "马坚", id: "zh.majian"),
        .init(language: "en", translator: "Ali Quli Qara’i", id: "en.qarai"),
        .init(language: "fr", translator: "Hamidullah", id: "fr.hamidullah"),
        .init(language: "de", translator: "Bubenheim & Elyas", id: "de.bubenheim"),
        .init(language: "id", translator: "Bahasa Indonesia", id: "id.indonesian"),
        .init(language: "it", translator: "Piccardo", id: "it.piccardo"),
        .init(language: "ms", translator: "Basmeih", id: "ms.basmeih"),
        .init(language: "fa", translator: "فولادوند", id: "fa.fooladvand"),
        .init(language: "ru", translator: "Кулиев", id: "ru.kuliev"),
        .init(language: "es", translator: "Bornez", id: "es.bornez"),
        .init(language: "tr", translator: "Diyanet Vakfı", id: "tr.vakfi"),
        .init(language: "ur", translator: "علامہ جوادی", id: "ur.jawadi"),
    ]

    static func preferred(in available: [QuranTranslation], locale: Locale) -> QuranTranslation? {
        let language = locale.language.languageCode?.identifier
        guard language != "ar" else { return nil }
        let script = locale.language.script?.identifier
        return available.first {
            let candidate = Locale(identifier: $0.language).language
            return candidate.languageCode?.identifier == language && candidate.script?.identifier == script
        } ?? available.first { Locale(identifier: $0.language).language.languageCode?.identifier == language }
    }
}
