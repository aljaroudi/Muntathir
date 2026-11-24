import Foundation
import Observation
import OSLog

protocol LibraryPackReader: Actor {
    init()
    func install(_ url: URL?) throws
    func replace(_ destination: URL, with staged: URL) throws
}

extension RulingsReader: LibraryPackReader {}
typealias RulingsAssetStore = LibraryPackStore<RulingsReader>

extension LibraryPackStore where Reader == RulingsReader {
    convenience init(backend: any AssetPackBackend = AppleAssetPackBackend(identifier: "rulings-v2", resourcePath: "Rulings/rulings.db"),
                     defaults: UserDefaults = .standard, library: URL? = nil)
    {
        self.init(packID: "rulings-v2", filename: "rulings/rulings.db", backend: backend, defaults: defaults, library: library)
    }
}

@MainActor @Observable final class LibraryPackStore<Reader: LibraryPackReader> {
    enum State { case checking, missing, downloading, ready, failed, incompatible }
    let reader = Reader()
    private let backend: any AssetPackBackend
    private(set) var state: State = .checking
    private(set) var progress: Progress?
    private(set) var installedBytes: Int64 = 0
    private(set) var revision = 0
    private(set) var busy = false
    var storageError = false
    private var pendingRefresh = false
    private var downloading = false
    private var checkingForUpdates = false
    /// An explicit download may replace an unreadable copy, even with the same pack version.
    private var replaceRequested = false
    private var signature: String?
    private let defaults: UserDefaults
    /// The app-owned copy that is read. Without one (tests and UI tests), the managed pack is read in place.
    private let library: URL?
    private let packID: String
    private var installedVersionKey: String {
        "\(packID).installedPackVersion"
    }

    private var installedVersion: Int? {
        defaults.object(forKey: installedVersionKey) as? Int
    }

    private var policy: AssetPackUpdatePolicy {
        AssetPackUpdatePolicy(packID: packID, defaults: defaults)
    }

    init(packID: String, filename: String, backend: any AssetPackBackend, defaults: UserDefaults = .standard, library: URL? = nil) {
        self.packID = packID
        self.backend = backend
        self.defaults = defaults
        let usesLibrary = backend is AppleAssetPackBackend && !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        self.library = library ?? (usesLibrary ? URL.applicationSupportDirectory.appending(path: "Libraries/" + filename) : nil)
    }

    /// Downloads a newer hosted pack when due; `refresh()` adopts it only if it passes validation.
    /// Any local copy qualifies, whatever its state, so a refresh still in flight cannot skip the check.
    func checkForUpdates(now: Date = .now, trigger: AssetPackUpdateTrigger = .foreground) async {
        guard let library, FileManager.default.fileExists(atPath: library.path), !downloading, !checkingForUpdates,
              policy.isDue(now, trigger: trigger) else { return }
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        do {
            guard let remote = try await backend.remoteVersion() else { return }
            policy.markChecked(now)
            guard policy.accepts(remote, over: installedVersion) else { return }
            if let installedVersion {
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                    .notice("Updating \(packID) from \(installedVersion) to \(remote).")
            }
            if await backend.localVersion() != remote {
                try await backend.download()
            }
            await refresh()
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                .error("Library update check failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The file to read. A managed pack replaces the library copy only after it validates, so a broken pack,
    /// or one this app version cannot read, never displaces working rulings. The managed pack is then removed.
    private func currentURL() async throws -> URL? {
        guard let library else { return try await backend.localURL() }
        let local = FileManager.default.fileExists(atPath: library.path) ? library : nil
        let replacing = replaceRequested
        replaceRequested = false
        guard let managed = try await backend.localURL() else { return local }
        let version = await backend.localVersion()
        if local != nil, !replacing {
            guard let version, policy.accepts(version, over: installedVersion) else {
                // Same or older, or already rejected: the managed pack is redundant.
                try? await backend.remove()
                return local
            }
        }
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
        do {
            try await Reader().install(managed)
        } catch {
            // An interrupted check proves nothing about the pack; keep it for the next refresh.
            if Task.isCancelled, let local {
                return local
            }
            // Without a copy to keep, the error surfaces as incompatible or failed.
            guard let local else { throw error }
            log.error("Rejected \(packID) pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            if let version {
                policy.reject(version)
            }
            try? await backend.remove()
            return local
        }
        do {
            let staged = try await Self.stage(managed, beside: library)
            defer { try? FileManager.default.removeItem(at: staged) }
            // Whatever file ends up in place, the next install must reopen it.
            signature = nil
            try await reader.replace(library, with: staged)
        } catch {
            if Task.isCancelled, let local {
                return local
            }
            guard let local else { throw error }
            // Storage failures are transient; the managed pack stays for the next refresh.
            log.error("Could not install library pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            return local
        }
        if let version {
            defaults.set(version, forKey: installedVersionKey)
        }
        log.notice("Installed \(packID) pack \(version ?? 0).")
        try? await backend.remove()
        return library
    }

    /// Copies a pack next to the library so the final swap is an atomic rename on the same volume.
    @concurrent private nonisolated static func stage(_ source: URL, beside destination: URL) async throws -> URL {
        let fm = FileManager.default
        var directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let staged = directory.appending(path: "staging-\(UUID().uuidString).db")
        do {
            try fm.copyItem(at: source, to: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return staged
    }

    func refresh() async {
        guard !busy else { pendingRefresh = true; return }
        busy = true
        do {
            if let url = try await currentURL() {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
                let current = "\(url.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(String(describing: values.fileResourceIdentifier))"
                if current != signature {
                    try await reader.install(url)
                    signature = current
                    revision += 1
                }
                installedBytes = Int64(values.fileSize ?? 0)
                state = .ready
            } else {
                try await reader.install(nil)
                signature = nil
                installedBytes = 0
                let active = await backend.isDownloading()
                state = downloading || active ? .downloading : .missing
            }
        } catch {
            signature = nil
            installedBytes = 0
            try? await reader.install(nil)
            if case HadithDatabaseError.incompatible = error {
                state = .incompatible
            } else {
                state = .failed
            }
        }
        busy = false
        if pendingRefresh {
            pendingRefresh = false; await refresh()
        }
    }

    func download() async {
        guard !downloading, !busy else { return }
        downloading = true
        state = .downloading
        progress = nil
        do {
            try await backend.download()
            downloading = false
            signature = nil
            replaceRequested = true
            await refresh()
        } catch {
            downloading = false
            state = .failed
        }
    }

    func remove() async {
        guard !busy, !downloading, state != .downloading else { return }
        busy = true
        do {
            let managed = try await backend.localURL()
            if library == nil || managed != nil {
                try await backend.remove()
            }
            try await reader.install(nil)
            if let library, FileManager.default.fileExists(atPath: library.path) {
                try FileManager.default.removeItem(at: library)
            }
            defaults.removeObject(forKey: installedVersionKey)
            policy.resetSchedule()
            signature = nil
            installedBytes = 0
            revision += 1
            state = .missing
        } catch { storageError = true }
        busy = false
        if pendingRefresh {
            pendingRefresh = false; await refresh()
        }
    }

    func monitor() async {
        for await event in backend.updates() {
            guard !Task.isCancelled else { return }
            // A background update keeps ready rulings readable and silent.
            switch event {
            case .began:
                if state != .ready {
                    state = .downloading
                }
            case let .progress(value):
                if state != .ready {
                    progress = value; state = .downloading
                }
            case .finished:
                signature = nil; await refresh()
            case .failed:
                if state != .ready {
                    state = .failed
                }
            }
        }
    }
}
