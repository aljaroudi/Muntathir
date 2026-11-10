import Foundation
import Observation
import OSLog

@MainActor @Observable final class HadithAssetStore {
    enum State: Equatable {
        case checking, missing, downloading, ready, failed, incompatible
    }

    let packID: String
    let reader: HadithReader
    private(set) var state: State = .checking
    private(set) var downloadProgress: Progress?
    var progress: Double {
        downloadProgress?.fractionCompleted ?? 0
    }

    private(set) var installedBytes: Int64 = 0
    private(set) var hasLocalAsset = false
    private(set) var revision = 0
    private(set) var busy = false
    private(set) var fullValidationCount = 0
    private(set) var integrityCheck: Task<Void, Never>?
    private var integrityWorker: Task<Void, Error>?
    private let validateIntegrity: @Sendable (URL) async throws -> Void
    private let defaults: UserDefaults
    private var validationKey: String {
        "\(packID).validated.v1"
    }

    private let backend: any AssetPackBackend
    private var installedSignature: String?
    private var refreshPending = false
    private var downloadGeneration = 0
    private var pendingDownload: Int?
    private var downloadTask: Task<Void, Error>?
    private var progressSample: (date: Date, fraction: Double)?
    private var transferFinishedAt: Date?

    init(backend: any AssetPackBackend = AppleAssetPackBackend(), packID: String = "hadith", reader: HadithReader = HadithReader(), defaults: UserDefaults = .standard,
         validateIntegrity: @escaping @Sendable (URL) async throws -> Void = { try HadithDatabase(url: $0).validate() })
    {
        self.packID = packID
        self.validateIntegrity = validateIntegrity
        self.defaults = defaults
        self.backend = backend
        self.reader = reader
    }

    isolated deinit { integrityWorker?.cancel() }

    func invalidateValidation() {
        integrityWorker?.cancel()
        installedSignature = nil
        defaults.removeObject(forKey: validationKey)
    }

    func refresh() async {
        guard !busy else { refreshPending = true; return }
        busy = true
        await resolve()
        await finishOperation()
    }

    private func resolve() async {
        do {
            let lookupStarted = ContinuousClock.now
            let localURL = try await backend.localURL()
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .debug("Hadith local URL lookup: \(lookupStarted.duration(to: .now))")
            guard let url = localURL else {
                hasLocalAsset = false
                installedBytes = 0
                integrityWorker?.cancel()
                try await reader.install(nil)
                installedSignature = nil
                defaults.removeObject(forKey: validationKey)
                let downloading = await backend.isDownloading()
                state = downloading || pendingDownload != nil ? .downloading : .missing
                return
            }
            hasLocalAsset = true
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            installedBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let signature = "validation-1|\(url.path)|\(attributes[.systemFileNumber] ?? "")|\(attributes[.size] ?? "")|\(modified)"
            if signature != installedSignature {
                integrityWorker?.cancel()
                state = .checking
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets").notice("Validating Hadith database.")
                let started = Date()
                let full = defaults.string(forKey: validationKey) != signature
                try await reader.install(url, fullValidation: false)
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                    .notice("Hadith compatibility check elapsed=\(Date().timeIntervalSince(started))s; background scan needed=\(full)")
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets").notice("Hadith database is ready.")
                installedSignature = signature
                revision += 1
                if full {
                    startIntegrityCheck(url: url, signature: signature)
                }
            }
            state = .ready
        } catch HadithDatabaseError.incompatible {
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            state = .incompatible
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
				.error("Asset validation failed for \(self.packID, privacy: .public): \(String(describing: error), privacy: .public)")
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            state = .failed
        }
    }

    private func startIntegrityCheck(url: URL, signature: String) {
        let validate = validateIntegrity
        let worker = Task.detached(priority: .utility) { try await validate(url) }
        integrityWorker = worker
        integrityCheck = Task { [weak self] in
            do {
                try await worker.value
                guard let self, !worker.isCancelled, installedSignature == signature else { return }
                defaults.set(signature, forKey: validationKey)
                fullValidationCount += 1
            } catch {
                guard let self, !worker.isCancelled, installedSignature == signature else { return }
                invalidateValidation()
                state = .failed
                revision += 1
                try? await reader.install(nil)
            }
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
                defaults.removeObject(forKey: validationKey)
                try await reader.install(nil)
                try await backend.remove()
                installedSignature = nil
                defaults.removeObject(forKey: validationKey)
            }
        } catch {
            pendingDownload = nil
            await resolve()
            if state != .ready, state != .incompatible {
                state = .failed
            }
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
            if busy {
                refreshPending = true; return
            }
            // An older compatible pack remains useful if an update fails offline.
            await refresh()
            if state != .ready, state != .incompatible {
                state = .failed
            }
        }
    }

    func remove() async {
        guard !busy else { return }
        busy = true
        integrityWorker?.cancel()
        state = .checking
        revision += 1
        downloadGeneration += 1
        pendingDownload = nil
        downloadTask?.cancel()
        downloadTask = nil
        do {
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            try await reader.install(nil)
            try await backend.remove()
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            hasLocalAsset = false
            installedBytes = 0
            state = .missing
        } catch {
            await resolve()
            if state != .ready {
                state = .failed
            }
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

    func receive(_ event: AssetPackEvent) async {
        switch event {
        case .began:
            if state != .ready {
                state = .downloading
            }
        case let .progress(value):
            if progressSample == nil {
                progressSample = (Date(), value.fractionCompleted)
            }
            downloadProgress = value
            if state != .ready {
                state = .downloading
            }
        case .finished:
            pendingDownload = nil
            await refresh()
            if state == .missing {
                state = .failed
            }
        case .failed:
            pendingDownload = nil
            if !busy {
                await refresh()
                if state != .ready, state != .incompatible {
                    state = .failed
                }
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
        if transferFinishedAt == nil {
            transferFinishedAt = date
        }
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

struct HadithSessionState: Codable, Equatable {
    var active = false
    var request = HadithRequest()
    var history: [HadithCursor] = []
    var selection: HadithSource?
    var listOffset: Double = 0
    var detailOffset: Double = 0
    var chapter: HadithSource?
    var cursorSources: [HadithSource?] = []
    // Optional fields keep sessions saved before contents navigation decodable.
    var screen: String?
    var contentsQuery: String?
    var contentsOffset: Double?
    var listRow: String?
    var contentsRow: String?
}

@MainActor @Observable final class HadithSession {
    var state: HadithSessionState {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private let key = "hadith.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HadithSessionState.self, from: $0) } ?? HadithSessionState()
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}
