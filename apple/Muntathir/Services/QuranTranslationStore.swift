import Foundation
import Observation
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
            if index.pending != nil {
                if let resource = try await backend.localURL() {
                    downloadState = .installing
                    try await files.install(from: resource.deletingLastPathComponent())
                    downloadState = .idle
                    completedTransferAt = nil
                    finishRequest()
                    changed()
                } else if await backend.isDownloading() || requesting {
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

    func download(requested: String? = nil) async {
        guard !busy, !requesting, !isDownloading else { return }
        busy = true
        storageError = false
        do {
            guard let files else { throw QuranDatabaseError.unavailable }
            // A failed installation may contain corrupt files; retry with a fresh managed pack.
            if downloadState == .failed, try files.read().pending != nil, try await backend.localURL() != nil {
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
        downloadState = .downloading
        downloadProgress = nil
        completedTransferAt = nil
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
            if (try? files?.read().pending) != nil {
                downloadState = .downloading
            }
        case let .progress(progress):
            downloadProgress = progress
        case .finished:
            await refresh()
        case .failed:
            finishRequest()
            await refresh()
            if (try? files?.read().pending) != nil {
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
