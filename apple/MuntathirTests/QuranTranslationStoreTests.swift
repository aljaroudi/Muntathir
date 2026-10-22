import Foundation
@testable import Muntathir
import Testing

private final class QuranTestBundleMarker: NSObject {}

enum QuranTestResources {
    static var translationURLs: [String: URL] {
        let bundle = Bundle(for: QuranTestBundleMarker.self)
        return Dictionary(uniqueKeysWithValues: QuranTranslation.catalog.compactMap { translation in
            bundle.url(forResource: translation.id, withExtension: "db", subdirectory: "Quran").map { (translation.id, $0) }
        })
    }
}

private actor QuranDownloadAttempt {
    private var attempts = 0

    func download(from source: URL, to destination: URL) throws {
        attempts += 1
        if attempts == 1 {
            throw QuranDatabaseError.unavailable
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

@MainActor struct QuranTranslationStoreTests {
    @Test(arguments: [
        ("en-GB", "en.qarai"), ("fr-FR", "fr.hamidullah"), ("fa-IR", "fa.fooladvand"),
        ("ur-PK", "ur.jawadi"), ("zh-Hans-CN", "zh.jian"), ("zh-Hant-TW", "zh.majian"),
        ("ar-SA", ""), ("ja-JP", ""),
    ])
    func autoMatchesLanguages(language: String, expected: String) {
        #expect(QuranTranslationPreferences.resolve("auto", languages: [language])?.id ?? "" == expected)
    }

    @Test func arabicStopsFallbackAndExplicitSelectionWins() {
        #expect(QuranTranslationPreferences.resolve("auto", languages: ["ar-SA", "en-US"]) == nil)
        #expect(QuranTranslationPreferences.resolve("auto", languages: ["ja-JP", "fr-FR"])?.id == "fr.hamidullah")
        #expect(QuranTranslationPreferences.resolve("", languages: ["en-US"]) == nil)
        #expect(QuranTranslationPreferences.resolve("ur.jawadi", languages: ["en-US"])?.id == "ur.jawadi")
    }

    @Test func allOriginalDatabasesAreValidAndArabicSurvivesBadTranslations() throws {
        let urls = QuranTestResources.translationURLs
        #expect(urls.count == 13)
        for url in urls.values {
            try QuranDatabase.validateTranslation(at: url)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not SQLite".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"), translationURLs: { ["en.qarai": folder] })
        let verses = try database.verses(surah: 1)
        #expect(verses.count == 7)
        #expect(verses.allSatisfy(\.translations.isEmpty))
        #expect(throws: QuranDatabaseError.self) { try QuranDatabase.validateTranslation(at: folder) }
    }

    @Test func failedDownloadRetriesPersistsAndRemovalClearsSelection() async throws {
        let suite = "QuranTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try #require(QuranTestResources.translationURLs["fr.hamidullah"])
        let attempt = QuranDownloadAttempt()
        let client = QuranAssetClient(url: { translation in
            let url = folder.appendingPathComponent("\(translation.id).db")
            guard FileManager.default.fileExists(atPath: url.path) else { throw QuranDatabaseError.unavailable }
            return url
        }, download: { translation in
            try await attempt.download(from: source, to: folder.appendingPathComponent("\(translation.id).db"))
        }, remove: { translation in
            try FileManager.default.removeItem(at: folder.appendingPathComponent("\(translation.id).db"))
        })
        let store = QuranTranslationStore(defaults: defaults, languages: ["fr-FR"], client: client, reloadWidgets: {})
        #expect(store.selection == "auto")
        #expect(store.activeID == "fr.hamidullah")
        await store.downloadSelected()
        #expect(store.statuses[store.activeID] == .failed)
        store.updateProgress(packID: "quran-fr-hamidullah", fraction: 0.5)
        #expect(store.statuses[store.activeID] == .downloading(0.5))
        store.select("fr.hamidullah")
        let retried = store
        retried.retryDownload()
        await retried.downloadSelected()
        #expect(retried.statuses[retried.activeID] == .installed)
        retried.activate(languages: ["ur-PK"])
        #expect(retried.activeID == "fr.hamidullah")
        let relaunched = QuranTranslationStore(defaults: defaults, languages: ["en"], client: client, reloadWidgets: {})
        #expect(relaunched.statuses["fr.hamidullah"] == .installed)
        try await relaunched.remove(#require(QuranTranslation.catalog.first { $0.id == "fr.hamidullah" }))
        #expect(relaunched.activeID.isEmpty)
        #expect(relaunched.selection.isEmpty)
        #expect(relaunched.statuses["fr.hamidullah"] == nil)
        #expect(defaults.string(forKey: QuranTranslationPreferences.resolvedKey) == "")
    }

    @Test func corruptAssetIsReplacedAndCancellationIsNotFailure() async throws {
        let source = try #require(QuranTestResources.translationURLs["en.qarai"])
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("corrupt".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let client = QuranAssetClient(url: { _ in
            guard FileManager.default.fileExists(atPath: destination.path) else { throw QuranDatabaseError.unavailable }
            return destination
        }, download: { _ in
            try FileManager.default.copyItem(at: source, to: destination)
        }, remove: { _ in try FileManager.default.removeItem(at: destination) })
        let store = QuranTranslationStore(defaults: nil, languages: ["en"], client: client, reloadWidgets: {})
        #expect(store.statuses["en.qarai"] == .failed)
        await store.downloadSelected()
        #expect(store.statuses["en.qarai"] == .installed)
        var cancelledClient = client
        cancelledClient.url = { _ in throw QuranDatabaseError.unavailable }
        cancelledClient.download = { _ in throw CancellationError() }
        let cancelled = QuranTranslationStore(defaults: nil, languages: ["en"], client: cancelledClient, reloadWidgets: {})
        await cancelled.downloadSelected()
        #expect(cancelled.statuses["en.qarai"] == nil)
    }

    @Test func noneNeverDownloadsAndAutoFollowsLocale() async {
        let client = QuranAssetClient(url: { _ in throw QuranDatabaseError.unavailable }, download: { _ in Issue.record("Unexpected download") }, remove: { _ in })
        let store = QuranTranslationStore(defaults: nil, languages: ["ar"], client: client, reloadWidgets: {})
        await store.downloadSelected()
        store.select("")
        store.activate(languages: ["en"])
        await store.downloadSelected()
        #expect(store.activeID.isEmpty)
        store.select("auto")
        #expect(store.activeID == "en.qarai")
        store.activate(languages: ["zh-Hant-TW"])
        #expect(store.activeID == "zh.majian")
    }
}
