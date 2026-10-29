import Foundation
@testable import Muntathir
import Testing

@MainActor struct QuranTranslationStoreTests {
    @Test func bundledTranslationsAreValid() throws {
        #expect(Set(QuranTranslation.catalog.map(\.id)) == ["en.qarai", "es.bornez", "de.bubenheim", "ru.kuliev", "zh.jian", "zh.majian"])
        for translation in QuranTranslation.catalog {
            try QuranDatabase.validateTranslation(at: QuranTranslationPreferences.url(for: translation))
        }
    }

    @Test func selectionPersistsAndNoneOverridesAuto() {
        let store = QuranTranslationStore(defaults: nil, languages: ["en"], reloadWidgets: {})
        #expect(store.activeID == "en.qarai")
        store.select("")
        store.activate(languages: ["de"])
        #expect(store.activeID.isEmpty)
        store.select("auto")
        #expect(store.activeID == "de.bubenheim")
    }
}

private final class QuranTestBundleMarker: NSObject {}

enum QuranTestResources {
    static var translationURLs: [String: URL] {
        let bundle = Bundle(for: QuranTestBundleMarker.self)
        return Dictionary(uniqueKeysWithValues: ["en.qarai", "es.bornez", "de.bubenheim", "ru.kuliev", "zh.jian", "zh.majian", "fr.hamidullah"].compactMap { id in
            bundle.url(forResource: id, withExtension: "db", subdirectory: "Quran").map { (id, $0) }
        })
    }
}
