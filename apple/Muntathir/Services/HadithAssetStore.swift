import Foundation
import Observation
import OSLog

@MainActor @Observable final class HadithAssetStore {
    enum State: Equatable {
        case checking, missing, downloading, installing, ready, failed, incompatible
    }

    private let library: HadithLocalLibrary?
    private(set) var books: [DownloadedBook] = []
    var storageError = false
    private(set) var storageErrorMessage = ""
    var isDownloading: Bool {
        state == .downloading || state == .installing
    }

    private var restorationKey: String {
        "\(packID).restoring"
    }

    private var cleanupKey: String {
        "\(packID).cleanup"
    }

    private var removedKey: String {
        "\(packID).removed"
    }

    /// The hosted pack version last copied into the local library.
    private var installedVersionKey: String {
        "\(packID).installedPackVersion"
    }

    private var installedVersion: Int? {
        defaults.object(forKey: installedVersionKey) as? Int
    }

    private var policy: AssetPackUpdatePolicy {
        AssetPackUpdatePolicy(packID: packID, defaults: defaults)
    }

    let packID: String
    let reader: HadithReader
    private(set) var state: State = .checking
    private(set) var downloadStarted = false
    var preparingDownload: Bool {
        isDownloading && !downloadStarted && downloadProgress == nil
    }

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
    private var checkingForUpdates = false

    init(backend: any AssetPackBackend = AppleAssetPackBackend(), packID: String = "hadith", reader: HadithReader = HadithReader(), defaults: UserDefaults = .standard, library: HadithLocalLibrary? = nil,
         validateIntegrity: @escaping @Sendable (URL) async throws -> Void = { try HadithDatabase(url: $0).validate() })
    {
        #if DEBUG
            if packID == AppleAssetPackBackend.packID, let fixture = HadithUITestFixture.downloadsDirectory {
                self.library = HadithLocalLibrary(root: fixture.appending(path: "Library"))
            } else {
                self.library = library ?? Self.defaultLibrary(backend: backend, packID: packID)
            }
        #else
            self.library = library ?? Self.defaultLibrary(backend: backend, packID: packID)
        #endif
        self.packID = packID
        self.validateIntegrity = validateIntegrity
        self.defaults = defaults
        self.backend = backend
        self.reader = reader
    }

    private static func defaultLibrary(backend: any AssetPackBackend, packID: String) -> HadithLocalLibrary? {
        guard backend is AppleAssetPackBackend, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        return HadithLocalLibrary(root: URL.applicationSupportDirectory.appending(path: "Libraries/\(packID)"))
    }

    isolated deinit { integrityWorker?.cancel() }

    func cancelIntegrityCheck() {
        integrityWorker?.cancel()
    }

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
        guard !defaults.bool(forKey: removedKey) else {
            state = .missing
            return
        }
        do {
            let lookupStarted = ContinuousClock.now
            var localURL = await library?.localURL()
            let restoring = defaults.string(forKey: restorationKey)
            var replacedLibrary = false
            if let library, localURL != nil {
                // Beside a working library, a managed pack is a requested restore, a newer version, or redundant.
                if let managed = try await backend.localURL() {
                    let version = await backend.localVersion()
                    if restoring != nil || version.map({ policy.accepts($0, over: installedVersion) }) == true {
                        replacedLibrary = await replace(library, from: managed, version: version, restoring: restoring)
                    } else {
                        defaults.set(true, forKey: cleanupKey)
                    }
                }
            } else if let managed = try await backend.localURL() {
                if let library {
                    state = .installing
                    let version = await backend.localVersion()
                    let staged = try await library.prepare(source: managed, restoring: restoring)
                    defer { try? FileManager.default.removeItem(at: staged) }
                    defaults.set(true, forKey: cleanupKey)
                    try await reader.commit(staged, to: library.url)
                    localURL = library.url
                    defaults.removeObject(forKey: restorationKey)
                    if let version {
                        defaults.set(version, forKey: installedVersionKey)
                    }
                } else {
                    localURL = managed
                }
            }
            if let library {
                books = try await library.books()
                if defaults.bool(forKey: cleanupKey) {
                    do {
                        try await backend.remove()
                        defaults.removeObject(forKey: cleanupKey)
                    } catch { storageErrorMessage = error.localizedDescription; storageError = true }
                }
            }
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
                if downloading, pendingDownload == nil {
                    downloadStarted = true
                }
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
                // An adopted pack was fully checked before the swap, so reading continues uninterrupted.
                if !replacedLibrary {
                    state = isDownloading ? .installing : .checking
                }
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
            let downloading = await backend.isDownloading()
            if defaults.string(forKey: restorationKey) != nil {
                state = pendingDownload != nil || downloading ? .downloading : .failed
            } else {
                state = .ready
            }
        } catch HadithDatabaseError.incompatible {
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            state = .incompatible
        } catch {
            if library != nil {
                storageErrorMessage = error.localizedDescription
                storageError = true
            }
            let packID = packID
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .error("Asset validation failed for \(packID, privacy: .public): \(String(describing: error), privacy: .public)")
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

    func download(title: String? = nil) async {
        guard !busy, state != .ready || title != nil, pendingDownload == nil else { return }
        if defaults.bool(forKey: removedKey) {
            guard title == nil else { return }
            defaults.removeObject(forKey: removedKey)
        }
        if let title {
            defaults.set(title, forKey: restorationKey)
        } else if library != nil, state == .failed || state == .incompatible,
                  defaults.string(forKey: restorationKey) == nil
        {
            defaults.set("", forKey: restorationKey)
        }
        let replaceInvalid = state == .incompatible || state == .failed
        busy = true
        state = .downloading
        downloadProgress = nil
        downloadStarted = false
        progressSample = nil
        transferFinishedAt = nil
        downloadGeneration += 1
        let generation = downloadGeneration
        pendingDownload = generation
        do {
            if replaceInvalid, try await backend.localURL() != nil {
                installedSignature = nil
                defaults.removeObject(forKey: validationKey)
                if library == nil {
                    try await reader.install(nil)
                }
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
        guard generation == downloadGeneration else { return }
        let backend = backend
        let request = Task {
            try Task.checkCancellation()
            try await backend.download()
        }
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
            guard generation == downloadGeneration else { return }
            if defaults.string(forKey: restorationKey) != nil || (state != .ready && state != .incompatible) {
                state = .failed
            }
        }
    }

    /// Replaces a working library only after read-only checks pass, so a broken pack, or one this app
    /// version cannot read, never displaces readable content. Returns whether the library changed.
    private func replace(_ library: HadithLocalLibrary, from managed: URL, version: Int?, restoring: String?) async -> Bool {
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
        let packID = packID
        do {
            try await library.verify(source: managed, supplications: packID == "supplications")
        } catch {
            // An interrupted check proves nothing about the pack; keep it for the next refresh.
            guard !Task.isCancelled else { return false }
            log.error("Rejected \(packID, privacy: .public) pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            if let version {
                policy.reject(version)
            }
            if restoring != nil {
                defaults.removeObject(forKey: restorationKey)
                storageErrorMessage = error.localizedDescription
                storageError = true
            }
            defaults.set(true, forKey: cleanupKey)
            return false
        }
        if restoring != nil {
            state = .installing
        }
        // A scan of the current file must not keep it open while it is replaced.
        integrityWorker?.cancel()
        do {
            let staged = try await library.prepare(source: managed, restoring: restoring)
            defer { try? FileManager.default.removeItem(at: staged) }
            try await reader.commit(staged, to: library.url)
        } catch {
            guard !Task.isCancelled else { return false }
            log.error("Could not install \(packID, privacy: .public) pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            if restoring != nil {
                // The restore stays retryable from the downloaded pack.
                storageErrorMessage = error.localizedDescription
                storageError = true
            } else {
                // Storage failures are transient; the next check downloads the update again.
                defaults.set(true, forKey: cleanupKey)
            }
            return false
        }
        defaults.set(true, forKey: cleanupKey)
        defaults.removeObject(forKey: restorationKey)
        if let version {
            defaults.set(version, forKey: installedVersionKey)
        }
        log.notice("Installed \(packID, privacy: .public) pack \(version ?? 0).")
        return true
    }

    /// Downloads a newer hosted pack when due; `resolve()` adopts it only if it passes validation.
    /// Any local library qualifies, whatever its state, so a refresh still in flight cannot skip the check.
    func checkForUpdates(now: Date = .now, trigger: AssetPackUpdateTrigger = .foreground) async {
        guard let library, !checkingForUpdates, pendingDownload == nil, !defaults.bool(forKey: removedKey),
              defaults.string(forKey: restorationKey) == nil, policy.isDue(now, trigger: trigger) else { return }
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
        let packID = packID
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        guard await library.localURL() != nil else { return }
        do {
            guard let remote = try await backend.remoteVersion() else { return }
            policy.markChecked(now)
            guard policy.accepts(remote, over: installedVersion) else { return }
            if let installedVersion {
                log.notice("Updating \(packID, privacy: .public) from \(installedVersion) to \(remote).")
            }
            if await backend.localVersion() != remote {
                try await backend.download()
            }
            await refresh()
        } catch {
            log.error("Update check failed for \(packID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func remove(title: String) async {
        guard let library, !busy, !isDownloading, books.contains(where: { $0.id == title && $0.installed }) else { return }
        busy = true
        storageError = false
        integrityWorker?.cancel()
        do {
            guard let source = await library.localURL() else { throw HadithDatabaseError.unavailable }
            let staged = try await library.prepare(source: source, removing: title)
            defer { try? FileManager.default.removeItem(at: staged) }
            try await reader.commit(staged, to: library.url)
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            await resolve()
        } catch { storageErrorMessage = error.localizedDescription; storageError = true }
        await finishOperation()
    }

    func remove() async {
        guard !busy else { return }
        busy = true
        storageError = false
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
            let managed = try await backend.localURL()
            let downloading = await backend.isDownloading()
            if library == nil || managed != nil || downloading {
                try await backend.remove()
            }
            try await library?.remove()
            defaults.set(true, forKey: removedKey)
            defaults.removeObject(forKey: restorationKey)
            defaults.removeObject(forKey: cleanupKey)
            defaults.removeObject(forKey: installedVersionKey)
            policy.resetSchedule()
            books = []
            installedSignature = nil
            defaults.removeObject(forKey: validationKey)
            hasLocalAsset = false
            installedBytes = 0
            state = .missing
        } catch {
            storageErrorMessage = error.localizedDescription
            storageError = true
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
        guard !defaults.bool(forKey: removedKey) else { return }
        switch event {
        case .began:
            downloadStarted = true
            if state != .ready, state != .installing {
                if state != .downloading {
                    downloadProgress = nil; progressSample = nil
                }
                state = .downloading
            }
        case let .progress(value):
            guard state != .ready, state != .installing else { return }
            if state == .downloading, value.fractionCompleted < progress {
                return
            }
            downloadStarted = true
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
            if state == .missing, !defaults.bool(forKey: removedKey) {
                state = .failed
            }
        case .failed:
            pendingDownload = nil
            if !busy {
                await refresh()
                if state != .ready, state != .incompatible, !defaults.bool(forKey: removedKey) {
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
        guard isDownloading else { return }
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
        await refresh()
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
    var searchRankingVersion: Int? = 2
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

    /// Bumped when an App Intent replaces the session, so the Hadith screen rebuilds from it.
    private(set) var generation = 0
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "hadith.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HadithSessionState.self, from: $0) } ?? HadithSessionState()
        if state.searchRankingVersion != 2 {
            state.searchRankingVersion = 2
            if !state.request.query.isEmpty {
                state.request.cursor = HadithCursor()
                state.history = []
                state.cursorSources = []
                state.listOffset = 0
                state.listRow = nil
            }
        }
    }

    func reset(to state: HadithSessionState) {
        self.state = state
        generation += 1
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}
