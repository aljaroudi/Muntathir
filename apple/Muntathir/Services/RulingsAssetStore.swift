import Foundation
import Observation

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
    private var signature: String?

    init(backend: any AssetPackBackend = AppleAssetPackBackend(identifier: "rulings", resourcePath: "Rulings/rulings.db")) {
        self.backend = backend
    }

    func refresh() async {
        guard !busy else { pendingRefresh = true; return }
        busy = true
        do {
            if let url = try await backend.localURL() {
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
            try await backend.remove()
            try await reader.install(nil)
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
            switch event {
            case .began: state = .downloading
            case let .progress(value): progress = value; state = .downloading
            case .finished: signature = nil; await refresh()
            case .failed: state = .failed
            }
        }
    }
}
