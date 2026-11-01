import Foundation
import Observation
import OSLog

@MainActor @Observable final class HadithAssetStore {
    enum State: Equatable {
        case checking, missing, downloading, ready, failed, incompatible
    }

    let reader: HadithReader
    private(set) var state: State = .checking
    private(set) var downloadProgress: Progress?
    var progress: Double { downloadProgress?.fractionCompleted ?? 0 }
    private(set) var revision = 0
    private(set) var busy = false
    private let backend: any HadithAssetBackend
    private var installedSignature: String?
    private var refreshPending = false
    private var downloadGeneration = 0
    private var pendingDownload: Int?
    private var downloadTask: Task<Void, Error>?
    private var progressSample: (date: Date, fraction: Double)?
    private var transferFinishedAt: Date?

    init(backend: any HadithAssetBackend = AppleHadithAssets(), reader: HadithReader = HadithReader()) {
        self.backend = backend
        self.reader = reader
    }

    func refresh() async {
        guard !busy else { refreshPending = true; return }
        busy = true
        await resolve()
        await finishOperation()
    }

    private func resolve() async {
        do {
            guard let url = try await backend.localURL() else {
                try await reader.install(nil)
                installedSignature = nil
                let downloading = await backend.isDownloading()
                state = downloading || pendingDownload != nil ? .downloading : .missing
                return
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let signature = "\(url.path)|\(attributes[.systemFileNumber] ?? "")|\(attributes[.size] ?? "")|\(attributes[.modificationDate] ?? "")"
            if signature != installedSignature {
                state = .checking
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets").notice("Validating Hadith database.")
                try await reader.install(url)
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets").notice("Hadith database is ready.")
                installedSignature = signature
                revision += 1
            }
            state = .ready
        } catch HadithDatabaseError.incompatible {
            installedSignature = nil
            state = .incompatible
        } catch {
            installedSignature = nil
            state = .failed
        }
    }

    func download() async {
        guard !busy, state != .ready, pendingDownload == nil else { return }
        let replaceInvalid = state == .incompatible || state == .failed
        busy = true
        state = .downloading
        downloadProgress = nil
        progressSample = nil
        transferFinishedAt = nil
        downloadGeneration += 1
        let generation = downloadGeneration
        pendingDownload = generation
        do {
            if replaceInvalid, try await backend.localURL() != nil {
                installedSignature = nil
                try await reader.install(nil)
                try await backend.remove()
                installedSignature = nil
            }
        } catch {
            pendingDownload = nil
            await resolve()
            if state != .ready && state != .incompatible { state = .failed }
            await finishOperation()
            return
        }
        // The network wait must not block finished events or local availability checks.
        await finishOperation()
        let backend = backend
        let request = Task { try await backend.download() }
        downloadTask = request
        do {
            try await request.value
            guard generation == downloadGeneration else { return }
            pendingDownload = nil
            downloadTask = nil
            await refresh()
        } catch {
            guard generation == downloadGeneration else { return }
            pendingDownload = nil
            downloadTask = nil
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .error("Hadith download request failed: \(String(describing: error), privacy: .public)")
            // An in-flight validation already determines whether the local content is usable.
            if busy { refreshPending = true; return }
            // An older compatible pack remains useful if an update fails offline.
            await refresh()
            if state != .ready && state != .incompatible { state = .failed }
        }
    }

    func remove() async {
        guard !busy else { return }
        busy = true
        state = .checking
        revision += 1
        downloadGeneration += 1
        pendingDownload = nil
        downloadTask?.cancel()
        downloadTask = nil
        do {
            installedSignature = nil
            try await reader.install(nil)
            try await backend.remove()
            installedSignature = nil
            state = .missing
        } catch {
            await resolve()
            if state != .ready { state = .failed }
        }
        await finishOperation()
    }

    private func finishOperation() async {
        while refreshPending {
            refreshPending = false
            await resolve()
        }
        busy = false
    }

    func receive(_ event: HadithAssetEvent) async {
        switch event {
        case .began:
            if state != .ready { state = .downloading }
        case let .progress(value):
            if progressSample == nil { progressSample = (Date(), value.fractionCompleted) }
            downloadProgress = value
            if state != .ready { state = .downloading }
        case .finished:
            pendingDownload = nil
            await refresh()
            if state == .missing { state = .failed }
        case .failed:
            pendingDownload = nil
            if !busy {
                await refresh()
                if state != .ready && state != .incompatible { state = .failed }
            }
        }
    }

    func estimatedRemaining(at date: Date) -> TimeInterval? {
        guard progress > 0, progress < 1 else { return nil }
        if let estimate = downloadProgress?.estimatedTimeRemaining, estimate.isFinite, estimate > 0 {
            return estimate
        }
        guard let sample = progressSample else { return nil }
        let elapsed = date.timeIntervalSince(sample.date)
        let advanced = progress - sample.fraction
        guard elapsed >= 2, advanced > 0 else { return nil }
        return elapsed * (1 - progress) / advanced
    }

    func reconcileDownload(at date: Date = Date()) async {
        guard state == .downloading else { return }
        await refresh()
        guard state == .downloading, progress >= 1 else { return }
        if transferFinishedAt == nil { transferFinishedAt = date }
        if let finished = transferFinishedAt, date.timeIntervalSince(finished) >= 120 {
            // A completed transfer must not strand the user if installation never finishes.
            downloadGeneration += 1
            pendingDownload = nil
            downloadTask?.cancel()
            downloadTask = nil
            state = .failed
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .error("Hadith transfer completed, but the managed database was not available after 120 seconds.")
        }
    }

    func monitor() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [backend] in
                for await event in backend.updates() {
                    guard !Task.isCancelled else { return }
                    await self.receive(event)
                }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                await reconcileDownload()
            }
            group.cancelAll()
        }
    }
}
