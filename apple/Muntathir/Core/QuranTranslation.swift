import Foundation

struct QuranTranslation: Identifiable, Hashable, Sendable {
    let language: String
    let translator: String
    let id: String
    let column: String

    static let catalog: [QuranTranslation] = [
        .init(language: "zh", translator: "马坚", id: "zh.jian", column: "zh_jian"),
        .init(language: "zh-Hant", translator: "马坚", id: "zh.majian", column: "zh_majian"),
        .init(language: "en", translator: "Ali Quli Qara’i", id: "en.qarai", column: "en_qarai"),
        .init(language: "fr", translator: "Hamidullah", id: "fr.hamidullah", column: "fr_hamidullah"),
        .init(language: "de", translator: "Bubenheim & Elyas", id: "de.bubenheim", column: "de_bubenheim"),
        .init(language: "id", translator: "Bahasa Indonesia", id: "id.indonesian", column: "id_indonesian"),
        .init(language: "it", translator: "Piccardo", id: "it.piccardo", column: "it_piccardo"),
        .init(language: "ms", translator: "Basmeih", id: "ms.basmeih", column: "ms_basmeih"),
        .init(language: "fa", translator: "فولادوند", id: "fa.fooladvand", column: "fa_fooladvand"),
        .init(language: "ru", translator: "Кулиев", id: "ru.kuliev", column: "ru_kuliev"),
        .init(language: "es", translator: "Bornez", id: "es.bornez", column: "es_bornez"),
        .init(language: "tr", translator: "Diyanet Vakfı", id: "tr.diyanet", column: "tr_diyanet"),
        .init(language: "ur", translator: "علامہ جوادی", id: "ur.jawadi", column: "ur_jawadi"),
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
