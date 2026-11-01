import BackgroundAssets
import Foundation
import OSLog
import System

protocol HadithAssetBackend: Sendable {
    func localURL() async throws -> URL?
    func isDownloading() async -> Bool
    func download() async throws
    func remove() async throws
    func updates() -> AsyncStream<HadithAssetEvent>
}

enum HadithAssetEvent: Sendable {
    case began
    case progress(Progress)
    case finished
    case failed
}

struct AppleHadithAssets: HadithAssetBackend {
    static let packID = "hadith"

    @concurrent func localURL() async throws -> URL? {
        // Resolving a local URL requires no network, including on iOS 26.0.
        do {
            let url = try AssetPackManager.shared.url(for: "Hadith/hadith.db")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .debug("Managed Hadith file is unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func isDownloading() async -> Bool {
        // localStatus reports installed content, not queued or active transfers.
        // Inspect the local queue without fetching a manifest or starting a download.
        guard let downloads = try? await BADownloadManager.shared.currentDownloads else { return false }
        return downloads.contains {
            $0.identifier == Self.packID && ($0.state == .waiting || $0.state == .downloading)
        }
    }

    func download() async throws {
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
        let manager = AssetPackManager.shared
        log.notice("Requesting Hadith asset manifest.")
        let pack: AssetPack
        if #available(iOS 27, *) {
            guard let value = try await manager.manifest.assetPack(withID: Self.packID) else {
                throw HadithDatabaseError.unavailable
            }
            pack = value
        } else {
            pack = try await manager.assetPack(withID: Self.packID)
        }
        log.notice("Hadith manifest resolved; requesting local availability.")
        if #available(iOS 26.4, *) {
            try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
        } else {
            try await manager.ensureLocalAvailability(of: pack)
        }
        log.notice("Hadith local availability confirmed.")
    }

    func remove() async throws {
        try await AssetPackManager.shared.remove(assetPackWithID: Self.packID)
    }

    func updates() -> AsyncStream<HadithAssetEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await update in AssetPackManager.shared.statusUpdates(forAssetPackWithID: Self.packID) {
                    guard !Task.isCancelled else { break }
                    switch update {
                    case .began: continuation.yield(.began)
                    case let .downloading(_, progress): continuation.yield(.progress(progress))
                    case .finished:
                        Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                            .notice("Hadith asset installation finished.")
                        continuation.yield(.finished)
                    case let .failed(_, error):
                        Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                            .error("Hadith asset download failed: \(String(describing: error), privacy: .public)")
                        continuation.yield(.failed)
                    case .paused: break
                    @unknown default: break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
