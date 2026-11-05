import Foundation

/// Arabic and English are bundled; other translations are installed in shared storage.
struct QuranTranslation: Identifiable, Hashable, Sendable {
    let language: String
    let translator: String
    let id: String

    static let catalog: [QuranTranslation] = [
        .init(language: "zh-Hans", translator: "马坚", id: "zh.jian"),
        .init(language: "zh-Hant", translator: "马坚", id: "zh.majian"),
        .init(language: "en", translator: "Ali Quli Qara’i", id: "en.qarai"),
        .init(language: "de", translator: "Bubenheim & Elyas", id: "de.bubenheim"),
        .init(language: "ru", translator: "Кулиев", id: "ru.kuliev"),
        .init(language: "es", translator: "Bornez", id: "es.bornez"),
        .init(language: "fa", translator: "فولادوند", id: "fa.fooladvand"),
        .init(language: "fr", translator: "Hamidullah", id: "fr.hamidullah"),
        .init(language: "id", translator: "Kementerian Agama", id: "id.indonesian"),
        .init(language: "it", translator: "Piccardo", id: "it.piccardo"),
        .init(language: "ms", translator: "Basmeih", id: "ms.basmeih"),
        .init(language: "tr", translator: "Diyanet Vakfı", id: "tr.vakfi"),
        .init(language: "ur", translator: "جوادی", id: "ur.jawadi"),
    ]

    static let bundledID = "en.qarai"
    static var downloadable: [QuranTranslation] {
        catalog.filter { $0.id != bundledID }
    }

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

/// Shared by the app and widget. Resolving a URL never starts a download.
enum QuranTranslationPreferences {
    static let groupID = "group.com.aljaroudi.Muntathir"
    static let selectionKey = "quranTranslationSelection"
    static let resolvedKey = "quranTranslationResolvedID"
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    static func resolve(_ selection: String, languages: [String]) -> QuranTranslation? {
        if selection != "auto" {
            return QuranTranslation.catalog.first { $0.id == selection }
        }
        for language in languages {
            let locale = Locale(identifier: language)
            // Arabic is itself a supported preference, so don't fall through to English.
            if locale.language.languageCode?.identifier == "ar" {
                return nil
            }
            if let translation = QuranTranslation.preferred(in: QuranTranslation.catalog, locale: locale) {
                return translation
            }
        }
        return nil
    }

    static var selected: QuranTranslation? {
        let selection = defaults?.string(forKey: selectionKey) ?? "auto"
        if selection == "auto", let resolved = defaults?.string(forKey: resolvedKey) {
            return QuranTranslation.catalog.first { $0.id == resolved }
        }
        return resolve(selection, languages: Locale.preferredLanguages)
    }

    static func url(for translation: QuranTranslation) throws -> URL {
        if translation.id != QuranTranslation.bundledID {
            guard let root = QuranTranslationFiles.sharedRoot,
                  let url = try QuranTranslationFiles(root: root).installedURLs()[translation.id]
            else {
                throw QuranDatabaseError.unavailable
            }
            return url
        }
        guard let url = Bundle.main.url(forResource: translation.id, withExtension: "db") else {
            throw QuranDatabaseError.unavailable
        }
        return url
    }
}
