import Foundation
@testable import Muntathir
import Testing

@MainActor struct QuranTranslationStoreTests {
    @Test func bundledTranslationsAreValid() throws {
        #expect(QuranTranslation.catalog.count == 13)
        #expect(QuranTranslation.downloadable.count == 12)
        let english = try #require(QuranTranslation.catalog.first { $0.id == QuranTranslation.bundledID })
        try QuranDatabase.validateTranslation(at: QuranTranslationPreferences.url(for: english))
        for translation in QuranTranslation.downloadable {
            #expect(Bundle.main.url(forResource: translation.id, withExtension: "db") == nil)
            let url = try #require(QuranTestResources.translationURLs[translation.id])
            try QuranDatabase.validateTranslation(at: url)
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
        return Dictionary(uniqueKeysWithValues: QuranTranslation.catalog.map(\.id).compactMap { id in
            bundle.url(forResource: id, withExtension: "db", subdirectory: "Quran").map { (id, $0) }
        })
    }
}
