import Foundation
import Observation
import OSLog
import WidgetKit

@MainActor @Observable final class QuranTranslationStore {
    static let shared = QuranTranslationStore()
    private(set) var selection: String
    private(set) var activeID: String
    private(set) var revision = 0
    private let defaults: UserDefaults?
    private let reloadWidgets: () -> Void
    private var languages: [String]
    enum DownloadState { case idle, downloading, installing, failed }
    private(set) var downloadState: DownloadState = .idle
    private(set) var downloadProgress: Progress?
    private var downloadStarted = false
    var preparingDownload: Bool {
        downloadState == .downloading && !downloadStarted
    }

    private(set) var installedSizes: [String: Int64] = [:]
    private(set) var busy = false
    var storageError = false
    var downloadRequest: QuranTranslation?
    private let backend: any AssetPackBackend
    private let files: QuranTranslationFiles?
    private var requesting = false
    private var requestTask: Task<Void, Error>?
    private var requestGeneration = 0
    private var completedTransferAt: Date?
    var isDownloading: Bool {
        downloadState == .downloading || downloadState == .installing
    }

    private var policy: AssetPackUpdatePolicy {
        AssetPackUpdatePolicy(packID: "quran-translations", defaults: defaults)
    }

    func isInstalled(_ id: String) -> Bool {
        id == QuranTranslation.bundledID || installedSizes[id] != nil
    }

    init(defaults: UserDefaults? = QuranTranslationPreferences.defaults, languages: [String] = Locale.preferredLanguages,
         backend: any AssetPackBackend = AppleAssetPackBackend(identifier: "quran-translations", resourcePath: "Quran/de.bubenheim.db"),
         directory: URL? = QuranTranslationFiles.sharedRoot,
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "DailyAyah") })
    {
        self.backend = backend
        files = directory.map { QuranTranslationFiles(root: $0) }
        self.defaults = defaults
        self.languages = languages
        self.reloadWidgets = reloadWidgets
        let saved = defaults?.string(forKey: QuranTranslationPreferences.selectionKey) ?? "auto"
        let initial = saved == "auto" || saved.isEmpty || QuranTranslation.catalog.contains(where: { $0.id == saved }) ? saved : "auto"
        selection = initial
        activeID = QuranTranslationPreferences.resolve(initial, languages: languages)?.id ?? ""
        publish()
    }

    func select(_ value: String) {
        guard value != selection else { return }
        guard value == "auto" || value.isEmpty || QuranTranslation.catalog.contains(where: { $0.id == value }) else { return }
        selection = value
        activeID = QuranTranslationPreferences.resolve(value, languages: languages)?.id ?? ""
        publish()
    }

    func activate(languages: [String]) {
        self.languages = languages
        let resolved = QuranTranslationPreferences.resolve(selection, languages: languages)?.id ?? ""
        if resolved != activeID {
            activeID = resolved
            publish()
        }
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let files else { throw QuranDatabaseError.unavailable }
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--ui-testing"), arguments.contains("--marketing-capture"),
                   arguments.contains("--marketing-local-translations"), try !files.read().hasInstalled,
                   let source = Bundle.main.url(forResource: "de.bubenheim", withExtension: "db", subdirectory: "MarketingQuran")
                {
                    try files.prepare(requested: nil)
                    try await files.install(from: source.deletingLastPathComponent())
                    var captured = try files.read()
                    captured.needsPackCleanup = false
                    try files.write(captured)
                }
            #endif
            let index = try files.read()
            if index.pending != nil, index.backgroundUpdate == true {
                await installUpdate(files)
            } else if index.pending != nil {
                if let resource = try await backend.localURL() {
                    downloadState = .installing
                    let directory = resource.deletingLastPathComponent()
                    let version = await backend.localVersion()
                    do {
                        try await files.verify(source: directory, version: version)
                    } catch {
                        if let version, !Task.isCancelled {
                            policy.reject(version)
                        }
                        throw error
                    }
                    try await files.install(from: directory, version: version)
                    downloadState = .idle
                    completedTransferAt = nil
                    finishRequest()
                    changed()
                } else if await backend.isDownloading() || requesting {
                    if !requesting {
                        downloadStarted = true
                    }
                    downloadState = .downloading
                } else {
                    downloadState = .failed
                }
            }
            if try files.read().needsPackCleanup {
                do {
                    try await backend.remove()
                    var cleaned = try files.read()
                    cleaned.needsPackCleanup = false
                    try files.write(cleaned)
                } catch {
                    storageError = true
                }
            }
            do { try files.cleanOrphans() }
            catch { storageError = true }
            try updateAvailability()
        } catch {
            finishRequest()
            downloadState = .failed
            try? updateAvailability()
        }
    }

    /// Installs a silent update without download UI. Any failure keeps the current languages: a broken or
    /// incompatible pack is skipped until a newer one or an app update, and storage failures retry next check.
    private func installUpdate(_ files: QuranTranslationFiles) async {
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
        guard let resource = try? await backend.localURL() else {
            if await !backend.isDownloading(), !requesting {
                abandonUpdate(files, removingPack: false)
            }
            return
        }
        let directory = resource.deletingLastPathComponent()
        let version = await backend.localVersion()
        do {
            try await files.verify(source: directory, version: version)
        } catch {
            // An interrupted check proves nothing about the pack; the update resumes on the next refresh.
            guard !Task.isCancelled else { return }
            log.error("Rejected Quran translation pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            if let version {
                policy.reject(version)
            }
            abandonUpdate(files, removingPack: true)
            return
        }
        do {
            try await files.install(from: directory, version: version)
            finishRequest()
            changed()
            log.notice("Quran translations updated to version \(version ?? 0).")
        } catch {
            guard !Task.isCancelled else { return }
            log.error("Quran translation update could not install: \(String(describing: error), privacy: .public)")
            abandonUpdate(files, removingPack: true)
        }
    }

    private func abandonUpdate(_ files: QuranTranslationFiles, removingPack: Bool) {
        guard var index = try? files.read(), index.backgroundUpdate == true else { return }
        index.pending = nil
        index.backgroundUpdate = nil
        index.needsPackCleanup = index.needsPackCleanup || removingPack
        try? files.write(index)
    }

    /// Whether a user-requested download is waiting to install.
    private var hasRequestedPending: Bool {
        guard let index = try? files?.read() else { return false }
        return index.pending != nil && index.backgroundUpdate != true
    }

    /// Silently reinstalls outdated languages from the latest hosted pack when due.
    func checkForUpdates(now: Date = .now, trigger: AssetPackUpdateTrigger = .foreground) async {
        guard let files, !busy, !requesting, !isDownloading, downloadState != .failed, policy.isDue(now, trigger: trigger),
              let index = try? files.read(), index.pending == nil, !index.installed.isEmpty else { return }
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
        let remote: Int
        do {
            guard let value = try await backend.remoteVersion() else { return }
            remote = value
        } catch {
            log.error("Quran translation update check failed: \(String(describing: error), privacy: .public)")
            return
        }
        policy.markChecked(now)
        guard policy.accepts(remote, over: index.packVersion) else { return }
        // The user may have started a download or deletion during the manifest request.
        guard !busy, !requesting, !isDownloading, (try? files.read().pending) == nil else { return }
        do { try files.prepareUpdate() } catch { return }
        log.notice("Updating Quran translations from \(index.packVersion ?? 0) to \(remote).")
        requesting = true
        requestGeneration += 1
        let generation = requestGeneration
        let task = Task { [backend] in try await backend.download() }
        requestTask = task
        do { try await task.value } catch {
            log.error("Quran translation update download failed: \(String(describing: error), privacy: .public)")
        }
        guard generation == requestGeneration else { return }
        requesting = false
        requestTask = nil
        await refresh()
        if hasRequestedPending {
            // A user request joined this transfer and it did not install.
            downloadState = .failed
        }
    }

    func download(requested: String? = nil) async {
        if requesting, !busy, let files, (try? files.read().backgroundUpdate) == true {
            // Join the in-flight update; its installation also adds the requested language.
            do { try files.prepare(requested: requested) } catch { return }
            downloadState = .downloading
            downloadStarted = false
            downloadProgress = nil
            completedTransferAt = nil
            return
        }
        guard !busy, !requesting, !isDownloading else { return }
        let retry = downloadState == .failed
        busy = true
        storageError = false
        downloadState = .downloading
        downloadStarted = false
        downloadProgress = nil
        completedTransferAt = nil
        do {
            guard let files else { throw QuranDatabaseError.unavailable }
            // A failed installation may contain corrupt files; retry with a fresh managed pack.
            if retry, try files.read().pending != nil, try await backend.localURL() != nil {
                try await backend.remove()
            }
            try files.prepare(requested: requested)
        } catch {
            busy = false
            downloadState = .failed
            return
        }
        requesting = true
        requestGeneration += 1
        let generation = requestGeneration
        busy = false
        let task = Task { [backend] in try await backend.download() }
        requestTask = task
        do {
            try await task.value
            guard generation == requestGeneration else { return }
            requesting = false
            requestTask = nil
            await refresh()
        } catch {
            guard generation == requestGeneration else { return }
            requesting = false
            requestTask = nil
            await refresh()
            if (try? files?.read().pending) != nil {
                downloadState = .failed
            }
        }
    }

    private func finishRequest() {
        requestGeneration += 1
        requesting = false
        requestTask?.cancel()
        requestTask = nil
    }

    func remove(_ ids: [String]) async {
        guard !busy, !isDownloading, !requesting else { return }
        busy = true
        storageError = false
        do {
            guard let files else { throw QuranDatabaseError.unavailable }
            // Abandon an interrupted request before deletion; it must not restore deleted files later.
            var index = try files.read()
            index.pending = nil
            index.needsPackCleanup = true
            try files.write(index)
            try files.remove(ids)
            try updateAvailability()
        } catch {
            storageError = true
            try? updateAvailability()
        }
        busy = false
        downloadState = .idle
        await refresh()
    }

    private func updateAvailability() throws {
        guard let files else { return }
        let sizes = try files.installedURLs().mapValues { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        if sizes != installedSizes {
            installedSizes = sizes
            changed()
        }
    }

    func receive(_ event: AssetPackEvent) async {
        switch event {
        case .began:
            if downloadState != .installing, hasRequestedPending {
                downloadStarted = true
                downloadState = .downloading
            }
        case let .progress(progress):
            guard downloadState == .downloading else { return }
            downloadStarted = true
            downloadProgress = progress
        case .finished:
            await refresh()
        case .failed:
            finishRequest()
            await refresh()
            if hasRequestedPending {
                downloadState = .failed
            }
        }
    }

    func reconcileDownload(at date: Date = .now) async {
        guard isDownloading else { return }
        await refresh()
        guard downloadState == .downloading, (downloadProgress?.fractionCompleted ?? 0) >= 1 else { return }
        if completedTransferAt == nil {
            completedTransferAt = date
        }
        if let completedTransferAt, date.timeIntervalSince(completedTransferAt) >= 120 {
            finishRequest()
            downloadState = .failed
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

    private func publish() {
        defaults?.set(selection, forKey: QuranTranslationPreferences.selectionKey)
        defaults?.set(activeID, forKey: QuranTranslationPreferences.resolvedKey)
        changed()
    }

    private func changed() {
        revision += 1
        reloadWidgets()
    }
}
