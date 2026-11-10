import Foundation
@testable import Muntathir
import Testing

@MainActor struct HadithAssetStoreTests {
    @Test func supplicationsHaveIndependentDownloadAndValidationState() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let suite = "IndependentAssets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let hadithBackend = TestHadithAssets(url: fixture.url)
        let prayerBackend = TestHadithAssets(url: fixture.url)
        let hadith = HadithAssetStore(backend: hadithBackend, defaults: defaults)
        let prayers = HadithAssetStore(backend: prayerBackend, packID: "supplications", defaults: defaults)
        await hadith.refresh()
        await prayers.download()
        await prayers.integrityCheck?.value
        #expect(prayers.state == .ready)
        #expect(hadith.state == .missing)
        #expect(await hadithBackend.downloads == 0)
        #expect(defaults.string(forKey: "supplications.validated.v1") != nil)
        #expect(defaults.string(forKey: "hadith.validated.v1") == nil)
        await hadith.download()
        await hadith.integrityCheck?.value
        await prayers.remove()
        #expect(prayers.state == .missing)
        #expect(hadith.state == .ready)
        #expect(defaults.string(forKey: "hadith.validated.v1") != nil)
    }

    @Test func explicitDownloadOfflineRelaunchAndRemoval() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        let store = HadithAssetStore(backend: backend)
        await store.refresh()
        #expect(store.state == .missing)
        #expect(await backend.downloads == 0)
        await store.download()
        #expect(store.state == .ready)
        #expect(try await store.reader.catalog().count == 2)
        let relaunched = HadithAssetStore(backend: backend)
        await relaunched.refresh()
        #expect(relaunched.state == .ready)
        #expect(await backend.downloads == 1)
        await backend.setFailure(true)
        await store.remove()
        #expect(store.state == .ready)
        #expect(try await store.reader.catalog().count == 2)
        await backend.setFailure(false)
        await store.remove()
        #expect(store.state == .missing)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.catalog() }
        await store.download()
        #expect(store.state == .ready)
        #expect(await backend.downloads == 2)
    }

    @Test func failureRetryAndInterruptedDownload() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setFailure(true)
        let store = HadithAssetStore(backend: backend)
        await store.download()
        #expect(store.state == .failed)
        await backend.setFailure(false)
        await backend.setDownloading(true)
        await store.refresh()
        #expect(store.state == .downloading)
        await store.download()
        #expect(store.state == .ready)
    }

    @Test func progressCompletionAndExternalRemovalRefreshReader() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        let store = HadithAssetStore(backend: backend)
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 40
        await store.receive(.progress(progress))
        #expect(store.state == .downloading)
        #expect(store.progress == 0.4)
        // Foundation updates the same object between status events.
        progress.completedUnitCount = 75
        #expect(store.progress == 0.75)
        await backend.setDownloading(true)
        await store.refresh()
        await store.receive(.began)
        #expect(store.downloadProgress === progress)
        #expect(store.progress == 0.75)
        try await backend.download()
        await store.receive(.finished)
        #expect(store.state == .ready)
        let revision = store.revision
        await store.refresh()
        #expect(store.revision == revision)
        try await backend.remove()
        await store.refresh()
        #expect(store.state == .missing)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.catalog() }
    }

    @Test func finishedEventOpensReaderWhileRequestStillWaits() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        await backend.suspendDownload()
        let store = HadithAssetStore(backend: backend)
        let request = Task { await store.download() }
        await backend.waitForDownload()
        #expect(!store.busy)
        await backend.setInstalled(true)
        await store.receive(.finished)
        #expect(store.state == .ready)
        #expect(try await store.reader.catalog().count == 2)
        await store.remove()
        await backend.resumeDownload()
        await request.value
        #expect(store.state == .missing)
    }

    @Test func completedTransferReconcilesWithoutFinishedEvent() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setDownloading(true)
        let store = HadithAssetStore(backend: backend)
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        await store.receive(.progress(progress))
        let now = Date()
        await store.reconcileDownload(at: now)
        #expect(store.state == .downloading)
        #expect(store.estimatedRemaining(at: now) == nil)
        await backend.setInstalled(true)
        await store.reconcileDownload(at: now.addingTimeInterval(2))
        #expect(store.state == .ready)
    }

    @Test func stalledInstallationBecomesRetryable() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setDownloading(true)
        let store = HadithAssetStore(backend: backend)
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        await store.receive(.progress(progress))
        let now = Date()
        await store.reconcileDownload(at: now)
        await store.reconcileDownload(at: now.addingTimeInterval(121))
        #expect(store.state == .failed)
        await store.download()
        #expect(store.state == .ready)
    }

    @Test func estimatedRemainingUsesLiveProgress() async throws {
        let store = HadithAssetStore(backend: TestHadithAssets(url: URL(filePath: "/unused")))
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 10
        await store.receive(.progress(progress))
        #expect(store.estimatedRemaining(at: Date()) == nil)
        progress.completedUnitCount = 50
        #expect(try #require(store.estimatedRemaining(at: Date().addingTimeInterval(10))) > 12)
        progress.estimatedTimeRemaining = 7
        #expect(store.estimatedRemaining(at: Date()) == 7)
        progress.completedUnitCount = 100
        #expect(store.estimatedRemaining(at: Date()) == nil)
    }

    @Test(arguments: [6, 999]) func incompatibleAndCorruptFilesAreRejected(version: Int) async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let write = try QuranConnection(path: fixture.url.path, flags: 2)
        try write.execute("PRAGMA user_version = \(version)")
        let backend = TestHadithAssets(url: fixture.url)
        let store = HadithAssetStore(backend: backend)
        await store.download()
        #expect(store.state == .incompatible)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.catalog() }
        try write.execute("PRAGMA user_version = 7")
        await store.download()
        #expect(store.state == .ready)
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("invalid".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        let broken = HadithAssetStore(backend: TestHadithAssets(url: corrupt))
        await broken.download()
        #expect(broken.state == .failed)
    }
}

private actor TestHadithAssets: AssetPackBackend {
    let url: URL
    var installed = false
    var downloads = 0
    var failing = false
    var downloading = false
    var suspended = false
    var waiter: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    init(url: URL) {
        self.url = url
    }

    func localURL() -> URL? {
        installed ? url : nil
    }

    func isDownloading() -> Bool {
        downloading
    }

    func setFailure(_ value: Bool) {
        failing = value
    }

    func setDownloading(_ value: Bool) {
        downloading = value
    }

    func suspendDownload() {
        suspended = true
    }

    func setInstalled(_ value: Bool) {
        installed = value
    }

    func waitForDownload() async {
        if downloads == 0 {
            await withCheckedContinuation { started = $0 }
        }
    }

    func resumeDownload() {
        waiter?.resume(); waiter = nil
    }

    func download() async throws {
        downloads += 1
        started?.resume()
        started = nil
        if suspended {
            await withCheckedContinuation { waiter = $0 }
        }
        try Task.checkCancellation()
        if failing {
            throw HadithDatabaseError.unavailable
        }
        installed = true
        downloading = false
    }

    func remove() throws {
        if failing {
            throw HadithDatabaseError.unavailable
        }
        installed = false
    }

    nonisolated func updates() -> AsyncStream<AssetPackEvent> {
        AsyncStream { $0.finish() }
    }
}

extension HadithAssetStoreTests {
    @Test func validationReceiptSurvivesRelaunchAndRemovalInvalidatesIt() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let suite = "HadithValidationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setInstalled(true)
        let first = HadithAssetStore(backend: backend, defaults: defaults)
        await first.refresh()
        await first.integrityCheck?.value
        let receipt = try #require(defaults.string(forKey: "hadith.validated.v1"))
        let second = HadithAssetStore(backend: backend, defaults: defaults)
        await second.refresh()
        #expect(second.state == .ready)
        #expect(first.fullValidationCount == 1)
        #expect(second.fullValidationCount == 0)
        #expect(defaults.string(forKey: "hadith.validated.v1") == receipt)
        let revision = second.revision
        await second.refresh()
        #expect(second.revision == revision)
        second.invalidateValidation()
        await second.refresh()
        await second.integrityCheck?.value
        #expect(second.fullValidationCount == 1)
        let modified = try #require(try FileManager.default.attributesOfItem(atPath: fixture.url.path)[.modificationDate] as? Date)
        try FileManager.default.setAttributes([.modificationDate: modified.addingTimeInterval(0.25)], ofItemAtPath: fixture.url.path)
        await second.refresh()
        await second.integrityCheck?.value
        #expect(second.fullValidationCount == 2)
        await second.remove()
        #expect(defaults.string(forKey: "hadith.validated.v1") == nil)
    }

    @Test func readingSessionRoundTripsWithoutTheLibrary() throws {
        let suite = "HadithSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = HadithSession(defaults: defaults)
        session.state.active = true
        session.state.request = HadithRequest(query: "mercy", collectionID: "bukhari", chapterID: 3, number: nil, cursor: HadithCursor(phase: .substring, afterID: 99))
        session.state.history = [HadithCursor()]
        session.state.selection = HadithSource(book: "bukhari", chapterFile: "1.json", number: 1, sourceID: 1)
        session.state.detailOffset = 480
        session.state.listOffset = 120
        let reopened = HadithSession(defaults: defaults)
        #expect(reopened.state == session.state)
        defaults.set(Data("broken".utf8), forKey: "hadith.session.v1")
        #expect(HadithSession(defaults: defaults).state == HadithSessionState())
    }
}

extension HadithAssetStoreTests {
    @Test func installedLibraryValidationTimings() async throws {
        let url = try #require(Bundle(for: HadithAssetTestBundle.self).url(forResource: "hadith", withExtension: "db"))
        let suite = "HadithTimingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = TestHadithAssets(url: url)
        await backend.setInstalled(true)
        let cold = HadithAssetStore(backend: backend, defaults: defaults)
        let clock = ContinuousClock()
        let coldTime = await clock.measure { await cold.refresh() }
        let catalogTime = try await clock.measure { _ = try await cold.reader.catalog() }
        await cold.integrityCheck?.value
        let relaunch = HadithAssetStore(backend: backend, defaults: defaults)
        let relaunchTime = await clock.measure { await relaunch.refresh() }
        let revision = relaunch.revision
        let foregroundTime = await clock.measure { await relaunch.refresh() }
        #expect(cold.state == .ready && relaunch.state == .ready)
        #expect(cold.fullValidationCount == 1)
        #expect(relaunch.fullValidationCount == 0)
        #expect(relaunch.revision == revision)
        let report = "Hadith asset checks: cold=\(coldTime), catalog=\(catalogTime), unchanged relaunch=\(relaunchTime), foreground=\(foregroundTime)"
        print(report)
        Attachment.record(report, named: "Hadith validation timings")
    }
}

private final class HadithAssetTestBundle: NSObject {}

extension HadithAssetStoreTests {
    @Test func slowIntegrityCheckDoesNotBlockReadingAndFailureInvalidatesReader() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let suite = "HadithAsyncValidation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (stream, release) = AsyncStream<Void>.makeStream()
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setInstalled(true)
        let store = HadithAssetStore(backend: backend, defaults: defaults) { _ in
            for await _ in stream {
                throw HadithDatabaseError.unavailable
            }
        }
        await store.refresh()
        #expect(store.state == .ready)
        #expect(try await store.reader.catalog().count == 2)
        #expect(defaults.string(forKey: "hadith.validated.v1") == nil)
        release.yield(())
        release.finish()
        await store.integrityCheck?.value
        #expect(store.state == .failed)
        #expect(defaults.string(forKey: "hadith.validated.v1") == nil)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.catalog() }
    }

    @Test func removingLibraryCancelsPendingIntegrityReceipt() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let suite = "HadithCancelledValidation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (stream, release) = AsyncStream<Void>.makeStream()
        let backend = TestHadithAssets(url: fixture.url)
        await backend.setInstalled(true)
        let store = HadithAssetStore(backend: backend, defaults: defaults) { _ in
            for await _ in stream {}
        }
        await store.refresh()
        await store.remove()
        release.finish()
        await store.integrityCheck?.value
        #expect(store.state == .missing)
        #expect(defaults.string(forKey: "hadith.validated.v1") == nil)
    }

    @Test func actualAssetLocatorTiming() async throws {
        let started = ContinuousClock.now
        let local = try await AppleAssetPackBackend().localURL()
        let report = "Apple asset locator: \(started.duration(to: .now)); installed=\(local != nil)"
        print(report)
        Attachment.record(report, named: "Apple asset locator timing")
    }
}
