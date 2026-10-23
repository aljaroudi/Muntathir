import BackgroundAssets
import Foundation
import Observation
import WidgetKit

struct QuranAssetClient: Sendable {
    var url: @Sendable (QuranTranslation) throws -> URL
    var download: @Sendable (QuranTranslation) async throws -> Void
    var remove: @Sendable (QuranTranslation) async throws -> Void

    static let live = QuranAssetClient(url: { try QuranTranslationPreferences.url(for: $0) }, download: { translation in
        guard QuranTranslationPreferences.assetManagerAvailable else { throw QuranDatabaseError.unavailable }
        let manager = AssetPackManager.shared
        let pack: AssetPack
        if #available(iOS 27, *) {
            guard let available = try await manager.manifest.assetPack(withID: translation.assetPackID) else { throw QuranDatabaseError.unavailable }
            pack = available
        } else {
            pack = try await manager.assetPack(withID: translation.assetPackID)
        }
        if #available(iOS 26.4, *) {
            try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
        } else {
            try await manager.ensureLocalAvailability(of: pack)
        }
    }, remove: {
        guard QuranTranslationPreferences.assetManagerAvailable else { throw QuranDatabaseError.unavailable }
        try await AssetPackManager.shared.remove(assetPackWithID: $0.assetPackID)
    })
}

@MainActor @Observable final class QuranTranslationStore {
    enum Status: Equatable {
        case downloading(Double?)
        case installed
        case failed
    }

    static let shared: QuranTranslationStore = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-state") {
                QuranTranslationPreferences.defaults?.removeObject(forKey: QuranTranslationPreferences.selectionKey)
                QuranTranslationPreferences.defaults?.removeObject(forKey: QuranTranslationPreferences.resolvedKey)
            }
        #endif
        return QuranTranslationStore()
    }()

    private(set) var selection: String
    private(set) var activeID: String
    private(set) var statuses: [String: Status] = [:]
    private(set) var revision = 0
    private(set) var retry = 0
    private let defaults: UserDefaults?
    private let client: QuranAssetClient
    private let reloadWidgets: () -> Void
    private var languages: [String]

    var downloadRequest: String {
        "\(activeID)-\(retry)"
    }

    init(defaults: UserDefaults? = QuranTranslationPreferences.defaults, languages: [String] = Locale.preferredLanguages,
         client: QuranAssetClient = .live, reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "DailyAyah") })
    {
        self.defaults = defaults
        self.languages = languages
        self.client = client
        self.reloadWidgets = reloadWidgets
        let saved = defaults?.string(forKey: QuranTranslationPreferences.selectionKey) ?? "auto"
        let initial = saved == "auto" || saved.isEmpty || QuranTranslation.catalog.contains(where: { $0.id == saved }) ? saved : "auto"
        selection = initial
        activeID = QuranTranslationPreferences.resolve(initial, languages: languages)?.id ?? ""
        publish()
        refresh()
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
        refresh()
    }

    func retryDownload() {
        retry += 1
    }

    func refresh() {
        for translation in QuranTranslation.catalog {
            if let url = try? client.url(translation) {
                statuses[translation.id] = (try? QuranDatabase.validateTranslation(at: url)) != nil ? .installed : .failed
            } else if statuses[translation.id] == .installed {
                statuses[translation.id] = nil
            }
        }
        changed()
    }

    func downloadSelected() async {
        guard let translation = QuranTranslation.catalog.first(where: { $0.id == activeID }), statuses[activeID] != .installed else { return }
        let corruptURL = try? client.url(translation)
        statuses[translation.id] = .downloading(nil)
        do {
            if let corruptURL, (try? QuranDatabase.validateTranslation(at: corruptURL)) == nil {
                try await client.remove(translation)
            }
            try await client.download(translation)
            try Task.checkCancellation()
            try QuranDatabase.validateTranslation(at: client.url(translation))
            statuses[translation.id] = .installed
            changed()
        } catch is CancellationError {
            // The system may finish the download after a selection or scene change.
            if case .downloading = statuses[translation.id] {
                statuses[translation.id] = nil
            }
        } catch {
            statuses[translation.id] = .failed
        }
    }

    func remove(_ translation: QuranTranslation) async {
        if case .downloading = statuses[translation.id] {
            return
        }
        if activeID == translation.id {
            select("")
        }
        do {
            try await client.remove(translation)
            statuses[translation.id] = nil
            changed()
        } catch {
            statuses[translation.id] = .failed
        }
    }

    func observeDownloads() async {
        guard QuranTranslationPreferences.assetManagerAvailable else { return }
        let updates = await AssetPackManager.shared.statusUpdates
        for await update in updates {
            guard !Task.isCancelled else { return }
            switch update {
            case let .downloading(pack, progress):
                updateProgress(packID: pack.id, fraction: progress.fractionCompleted)
            case let .began(pack), let .paused(pack):
                updateProgress(packID: pack.id, fraction: nil)
            case .finished:
                refresh()
            case let .failed(pack, _):
                if let translation = QuranTranslation.catalog.first(where: { $0.assetPackID == pack.id }) {
                    statuses[translation.id] = .failed
                }
            @unknown default: break
            }
        }
    }

    func updateProgress(packID: String, fraction: Double?) {
        guard let translation = QuranTranslation.catalog.first(where: { $0.assetPackID == packID }) else { return }
        statuses[translation.id] = .downloading(fraction.map { min(1, max(0, $0)) })
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
