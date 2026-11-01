import Foundation
@testable import Muntathir
import Testing

@MainActor struct HadithAssetStoreTests {
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

    @Test func estimatedRemainingUsesLiveProgress() async {
        let store = HadithAssetStore(backend: TestHadithAssets(url: URL(filePath: "/unused")))
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 10
        await store.receive(.progress(progress))
        #expect(store.estimatedRemaining(at: Date()) == nil)
        progress.completedUnitCount = 50
        #expect(store.estimatedRemaining(at: Date().addingTimeInterval(10))! > 12)
        progress.estimatedTimeRemaining = 7
        #expect(store.estimatedRemaining(at: Date()) == 7)
        progress.completedUnitCount = 100
        #expect(store.estimatedRemaining(at: Date()) == nil)
    }

    @Test func incompatibleAndCorruptFilesAreRejected() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let write = try QuranConnection(path: fixture.url.path, flags: 2)
        try write.execute("PRAGMA user_version = 999")
        let backend = TestHadithAssets(url: fixture.url)
        let store = HadithAssetStore(backend: backend)
        await store.download()
        #expect(store.state == .incompatible)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.catalog() }
        try write.execute("PRAGMA user_version = 6")
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

private actor TestHadithAssets: HadithAssetBackend {
    let url: URL
    var installed = false
    var downloads = 0
    var failing = false
    var downloading = false
    var suspended = false
    var waiter: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    init(url: URL) { self.url = url }
    func localURL() -> URL? { installed ? url : nil }
    func isDownloading() -> Bool { downloading }
    func setFailure(_ value: Bool) { failing = value }
    func setDownloading(_ value: Bool) { downloading = value }
    func suspendDownload() { suspended = true }
    func setInstalled(_ value: Bool) { installed = value }
    func waitForDownload() async {
        if downloads == 0 { await withCheckedContinuation { started = $0 } }
    }
    func resumeDownload() { waiter?.resume(); waiter = nil }
    func download() async throws {
        downloads += 1
        started?.resume()
        started = nil
        if suspended { await withCheckedContinuation { waiter = $0 } }
        try Task.checkCancellation()
        if failing { throw HadithDatabaseError.unavailable }
        installed = true
        downloading = false
    }
    func remove() throws {
        if failing { throw HadithDatabaseError.unavailable }
        installed = false
    }
    nonisolated func updates() -> AsyncStream<HadithAssetEvent> { AsyncStream { $0.finish() } }
}
