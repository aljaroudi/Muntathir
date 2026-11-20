import Foundation
@testable import Muntathir
import Testing

@MainActor struct QuranAssetStoreTests {
    @Test func brokenTranslationUpdateIsSkippedAndLanguagesKept() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: bad) }
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        for (id, url) in QuranTestResources.translationURLs {
            try FileManager.default.copyItem(at: url, to: bad.appending(path: "\(id).db"))
        }
        try Data("invalid".utf8).write(to: bad.appending(path: "es.bornez.db"), options: .atomic)
        let suite = "BrokenTranslations.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = QuranTestBackend(source: source)
        await backend.setRemote(1)
        let store = QuranTranslationStore(defaults: defaults, backend: backend, directory: root, reloadWidgets: {})
        await store.download()
        #expect(store.installedSizes.count == 12)

        await backend.serve(bad.appending(path: "de.bubenheim.db"))
        await backend.setRemote(2)
        let start = Date()
        await store.checkForUpdates(now: start)
        #expect(await backend.downloads == 2)
        #expect(store.downloadState == .idle)
        #expect(!store.storageError)
        #expect(store.installedSizes.count == 12)
        let files = QuranTranslationFiles(root: root)
        #expect(try files.read().packVersion == 1)
        #expect(try files.read().pending == nil)
        #expect(await backend.installed == false)

        // The rejected version is skipped.
        await store.checkForUpdates(now: start.addingTimeInterval(86400 * 2))
        #expect(await backend.downloads == 2)

        // A fixed, newer pack is adopted.
        await backend.serve(nil)
        await backend.setRemote(3)
        await store.checkForUpdates(now: start.addingTimeInterval(86400 * 4))
        #expect(await backend.downloads == 3)
        #expect(try files.read().packVersion == 3)
        #expect(store.installedSizes.count == 12)
    }

    @Test func outdatedTranslationsUpdateSilentlyWithoutRestoringDeletions() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        await backend.setRemote(1)
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        await store.download()
        await store.remove(["es.bornez"])
        let files = QuranTranslationFiles(root: root)
        #expect(try files.read().packVersion == 1)
        #expect(store.installedSizes.count == 11)

        await store.checkForUpdates()
        #expect(await backend.downloads == 1)

        await backend.setRemote(2)
        await store.checkForUpdates()
        #expect(await backend.downloads == 2)
        #expect(store.downloadState == .idle)
        #expect(store.installedSizes.count == 11)
        #expect(!store.isInstalled("es.bornez"))
        #expect(try files.read().packVersion == 2)
        #expect(try files.read().pending == nil)
        #expect(await backend.installed == false)

        // A failed update keeps the installed languages and shows no download failure.
        await backend.setRemote(3)
        await backend.failDownload(true)
        await store.checkForUpdates()
        #expect(store.downloadState == .idle)
        #expect(store.installedSizes.count == 11)
        #expect(try files.read().pending == nil)
        #expect(try files.read().packVersion == 2)

        // A restore from a newer pack refreshes the other installed languages too.
        await backend.failDownload(false)
        await store.download(requested: "es.bornez")
        #expect(store.installedSizes.count == 12)
        #expect(try files.read().packVersion == 3)
    }

    private func fixture() throws -> (URL, URL) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let source = try #require(QuranTestResources.translationURLs["de.bubenheim"])
        return (root, source)
    }

    @Test func installDeleteRestoreAndOfflineRelaunch() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        var widgetReloads = 0
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: { widgetReloads += 1 })
        await store.refresh()
        #expect(store.installedSizes.isEmpty)
        #expect(store.isInstalled("en.qarai"))
        #expect(await backend.downloads == 0)
        store.select("de.bubenheim")
        let initialReloads = widgetReloads
        await store.download(requested: "de.bubenheim")
        #expect(store.installedSizes.count == 12)
        #expect(store.downloadState == .idle)
        #expect(await backend.installed == false)
        #expect(widgetReloads > initialReloads)
        let installedReloads = widgetReloads
        let revision = store.revision
        await store.remove(["de.bubenheim", "es.bornez"])
        #expect(store.installedSizes.count == 10)
        #expect(store.activeID == "de.bubenheim")
        #expect(store.revision > revision)
        #expect(widgetReloads > installedReloads)
        await store.download(requested: "de.bubenheim")
        #expect(store.installedSizes.count == 11)
        #expect(!store.isInstalled("es.bornez"))
        #expect(await backend.downloads == 2)
        let relaunched = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        await relaunched.refresh()
        #expect(relaunched.installedSizes.count == 11)
        #expect(await backend.downloads == 2)
        await relaunched.remove(QuranTranslation.downloadable.map(\.id))
        #expect(relaunched.installedSizes.isEmpty)
        #expect(relaunched.isInstalled("en.qarai"))
        await relaunched.download(requested: "ru.kuliev")
        #expect(Set(relaunched.installedSizes.keys) == ["ru.kuliev"])
    }

    @Test func cleanupFailureNeverReinstallsDeletedLanguages() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        await backend.failRemoval(true)
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        await store.download()
        #expect(store.storageError)
        #expect(store.installedSizes.count == 12)
        await store.remove(["de.bubenheim"])
        let files = QuranTranslationFiles(root: root)
        #expect(try files.read().needsPackCleanup)
        let relaunched = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        await backend.failRemoval(false)
        await relaunched.refresh()
        #expect(!relaunched.isInstalled("de.bubenheim"))
        #expect(relaunched.installedSizes.count == 11)
        #expect(try !files.read().needsPackCleanup)
        #expect(await backend.downloads == 1)
    }

    @Test func interruptedRequestRecoversLocallyWithoutNetwork() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = QuranTranslationFiles(root: root)
        try files.prepare(requested: "de.bubenheim")
        let backend = QuranTestBackend(source: source)
        await backend.setInstalled(true)
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        await store.refresh()
        #expect(store.installedSizes.count == 12)
        #expect(await backend.downloads == 0)
        #expect(try files.read().pending == nil)
    }

    @Test func networkFailureCanRetry() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        await backend.suspendDownload()
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        let request = Task { await store.download() }
        await backend.waitForRequest()
        #expect(store.isDownloading)
        #expect(store.preparingDownload)
        #expect(store.downloadProgress == nil)

        await store.receive(.began)
        #expect(!store.preparingDownload)
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 40
        await store.receive(.progress(progress))
        #expect(store.downloadProgress?.fractionCompleted == 0.4)

        await backend.failDownload(true)
        await backend.resumeDownload()
        await request.value
        #expect(store.downloadState == .failed)
        #expect(!store.preparingDownload)
        #expect(store.installedSizes.isEmpty)

        await backend.failDownload(false)
        await backend.suspendDownload()
        let retry = Task { await store.download() }
        await backend.waitForRequest()
        #expect(store.preparingDownload)
        #expect(store.downloadProgress == nil)
        await backend.resumeDownload()
        await retry.value
        #expect(store.installedSizes.count == 12)
    }

    @Test func corruptOrOutOfSpaceInstallPreservesPublishedFiles() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = QuranTranslationFiles(root: root)
        try files.prepare(requested: nil)
        try await files.install(from: source.deletingLastPathComponent())
        let original = try files.installedURLs()
        try files.prepare(requested: "de.bubenheim")
        await #expect(throws: CocoaError.self) {
            try await files.install(from: source.deletingLastPathComponent()) { _, _ in
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        #expect(try files.installedURLs() == original)
        await #expect(throws: QuranDatabaseError.self) {
            try await files.install(from: source.deletingLastPathComponent()) { _, target in
                try Data("invalid SQLite".utf8).write(to: target)
            }
        }
        #expect(try files.installedURLs() == original)
        #expect(try files.read().pending == ["de.bubenheim"])
        try await files.install(from: source.deletingLastPathComponent())
        #expect(try files.read().pending == nil)
        try files.cleanOrphans()
        #expect(try !FileManager.default.fileExists(atPath: #require(original["de.bubenheim"]).path))
    }

    @Test func finishedEventInstallsWhileRequestWaitsAndLateResultCannotRestoreDeletedLanguage() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        await backend.suspendDownload()
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        let request = Task { await store.download() }
        await backend.waitForRequest()
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 60
        await store.receive(.progress(progress))
        #expect(store.downloadProgress?.fractionCompleted == 0.6)
        await backend.setInstalled(true)
        await store.receive(.finished)
        #expect(store.installedSizes.count == 12)
        await store.remove(["de.bubenheim"])
        await backend.resumeDownload()
        await request.value
        #expect(!store.isInstalled("de.bubenheim"))
        #expect(store.downloadState == .idle)
    }

    @Test func stalledCompletedTransferBecomesRetryable() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = QuranTestBackend(source: source)
        await backend.suspendDownload()
        let store = QuranTranslationStore(defaults: nil, backend: backend, directory: root, reloadWidgets: {})
        let request = Task { await store.download() }
        await backend.waitForRequest()
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        await store.receive(.progress(progress))
        let start = Date()
        await store.reconcileDownload(at: start)
        await store.reconcileDownload(at: start.addingTimeInterval(121))
        #expect(store.downloadState == .failed)
        await backend.resumeDownload()
        await request.value
        await store.download()
        #expect(store.installedSizes.count == 12)
    }

    @Test func missingTranslationLeavesArabicReadable() throws {
        let (root, _) = try fixture()
        let files = QuranTranslationFiles(root: root)
        let arabic = try #require(Bundle.main.url(forResource: "quran", withExtension: "db"))
        let database = QuranDatabase(url: arabic, translationURLs: { (try? files.installedURLs()) ?? [:] })
        let verse = try #require(try database.verse(surah: 1, number: 1))
        #expect(!verse.text.isEmpty)
        #expect(verse.translations.isEmpty)
    }
}

private actor QuranTestBackend: AssetPackBackend {
    let source: URL
    var installed = false
    var downloads = 0
    var version: Int?
    var remote: Int?
    var served: URL?
    private var removalFails = false
    private var downloadFails = false
    private var suspend = false
    private var gate: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(source: URL) {
        self.source = source
    }

    func localURL() -> URL? {
        installed ? served ?? source : nil
    }

    /// Serves a different pack directory, such as a broken pack, in place of `source`.
    func serve(_ value: URL?) {
        served = value
    }

    func isDownloading() -> Bool {
        false
    }

    func download() async throws {
        downloads += 1
        if suspend {
            await withCheckedContinuation { continuation in
                gate = continuation
                waiter?.resume()
                waiter = nil
            }
        }
        try Task.checkCancellation()
        if downloadFails {
            throw URLError(.notConnectedToInternet)
        }
        installed = true
        version = remote ?? version
    }

    func localVersion() -> Int? {
        installed ? version : nil
    }

    func remoteVersion() -> Int? {
        remote
    }

    func setRemote(_ value: Int?) {
        remote = value
    }

    func remove() throws {
        if removalFails {
            throw CocoaError(.fileWriteNoPermission)
        }
        installed = false
    }

    func suspendDownload() {
        suspend = true
    }

    func waitForRequest() async {
        if gate != nil {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func resumeDownload() {
        suspend = false
        gate?.resume()
        gate = nil
    }

    func failRemoval(_ value: Bool) {
        removalFails = value
    }

    func failDownload(_ value: Bool) {
        downloadFails = value
    }

    func setInstalled(_ value: Bool) {
        installed = value
    }

    nonisolated func updates() -> AsyncStream<AssetPackEvent> {
        AsyncStream { $0.finish() }
    }
}
