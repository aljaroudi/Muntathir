import Foundation
import Observation
import OSLog

@MainActor @Observable final class RulingsAssetStore {
    enum State { case checking, missing, downloading, ready, failed, incompatible }
    let reader = RulingsReader()
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
    private let installedVersionKey = "rulings.installedPackVersion"

    private var installedVersion: Int? {
        defaults.object(forKey: installedVersionKey) as? Int
    }

    private var policy: AssetPackUpdatePolicy {
        AssetPackUpdatePolicy(packID: "rulings", defaults: defaults)
    }

    init(backend: any AssetPackBackend = AppleAssetPackBackend(identifier: "rulings", resourcePath: "Rulings/rulings.db"),
         defaults: UserDefaults = .standard, library: URL? = nil)
    {
        self.backend = backend
        self.defaults = defaults
        self.library = library ?? Self.defaultLibrary(backend: backend)
    }

    private static func defaultLibrary(backend: any AssetPackBackend) -> URL? {
        guard backend is AppleAssetPackBackend, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        return URL.applicationSupportDirectory.appending(path: "Libraries/rulings/rulings.db")
    }

    /// Downloads a newer hosted pack at most once per day; `refresh()` adopts it only if it passes validation.
    func checkForUpdates(now: Date = .now) async {
        // An incompatible copy is unreadable anyway, so it may update too.
        guard library != nil, state == .ready || state == .incompatible, !busy, !downloading, !checkingForUpdates,
              policy.isDue(now) else { return }
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        do {
            guard let remote = try await backend.remoteVersion() else { return }
            policy.markChecked(now)
            guard policy.accepts(remote, over: installedVersion) else { return }
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                .notice("Updating rulings from \(self.installedVersion ?? 0) to \(remote).")
            if await backend.localVersion().map({ $0 < remote }) ?? true {
                try await backend.download()
            }
            await refresh()
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                .error("Rulings update check failed: \(String(describing: error), privacy: .public)")
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
            try await RulingsReader().install(managed)
        } catch {
            // Without a copy to keep, the error surfaces as incompatible or failed.
            guard let local else { throw error }
            log.error("Rejected rulings pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            if let version {
                policy.reject(version)
            }
            try? await backend.remove()
            return local
        }
        do {
            try await Self.copy(managed, to: library)
        } catch {
            guard let local else { throw error }
            // Storage failures are transient; the managed pack stays for the next refresh.
            log.error("Could not install rulings pack \(version ?? 0): \(String(describing: error), privacy: .public)")
            return local
        }
        if let version {
            defaults.set(version, forKey: installedVersionKey)
        }
        try? await backend.remove()
        return library
    }

    /// Readers of the previous file keep it open until they reinstall; the swap itself is atomic.
    @concurrent nonisolated private static func copy(_ source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        var directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let staged = directory.appending(path: "staging-\(UUID().uuidString).db")
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: source, to: staged)
        guard rename(staged.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
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
