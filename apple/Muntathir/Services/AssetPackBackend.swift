import BackgroundAssets
import Foundation
import OSLog
import System

protocol AssetPackBackend: Sendable {
    func localURL() async throws -> URL?
    func isDownloading() async -> Bool
    func download() async throws
    func remove() async throws
    func updates() -> AsyncStream<AssetPackEvent>
}

enum AssetPackEvent: Sendable {
    case began
    case progress(Progress)
    case finished
    case failed
}

struct AppleAssetPackBackend: AssetPackBackend {
    static let packID = "hadith"
    var identifier = Self.packID
    var resourcePath = "Hadith/hadith.db"

    @concurrent func localURL() async throws -> URL? {
        #if DEBUG
            if identifier == Self.packID, ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--marketing-capture"),
               let url = Bundle.main.url(forResource: "hadith", withExtension: "db", subdirectory: "Hadith")
            {
                return url
            }
            if identifier == Self.packID, ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-testing-hadith-fixture")
            {
                return try HadithUITestFixture.url()
            }
        #endif
        // Resolving a local URL requires no network, including on iOS 26.0.
        do {
            let url = try AssetPackManager.shared.url(for: FilePath(resourcePath))
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                .debug("Managed asset file is unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func isDownloading() async -> Bool {
        // localStatus reports installed content, not queued or active transfers.
        // Inspect the local queue without fetching a manifest or starting a download.
        guard let downloads = try? await BADownloadManager.shared.currentDownloads else { return false }
        return downloads.contains {
            $0.identifier == identifier && ($0.state == .waiting || $0.state == .downloading)
        }
    }

    func download() async throws {
        let log = Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
        let manager = AssetPackManager.shared
        log.notice("Requesting asset manifest: \(identifier, privacy: .public).")
        let pack: AssetPack
        if #available(iOS 27, *) {
            guard let value = try await manager.manifest.assetPack(withID: identifier) else {
                throw HadithDatabaseError.unavailable
            }
            pack = value
        } else {
            pack = try await manager.assetPack(withID: identifier)
        }
        log.notice("Manifest resolved; requesting local availability.")
        if #available(iOS 26.4, *) {
            try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
        } else {
            try await manager.ensureLocalAvailability(of: pack)
        }
        log.notice("Asset local availability confirmed.")
    }

    func remove() async throws {
        try await AssetPackManager.shared.remove(assetPackWithID: identifier)
    }

    func updates() -> AsyncStream<AssetPackEvent> {
        #if DEBUG
            // Capture/test databases have no hosted download events or hosting entitlements.
            let arguments = ProcessInfo.processInfo.arguments
            if identifier == Self.packID, arguments.contains("--ui-testing"),
               arguments.contains("--marketing-capture") || arguments.contains("--ui-testing-hadith-fixture")
            {
                return AsyncStream { $0.finish() }
            }
        #endif
        return AsyncStream { continuation in
            let task = Task {
                for await update in AssetPackManager.shared.statusUpdates(forAssetPackWithID: identifier) {
                    guard !Task.isCancelled else { break }
                    switch update {
                    case .began: continuation.yield(.began)
                    case let .downloading(_, progress): continuation.yield(.progress(progress))
                    case .finished:
                        Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                            .notice("Asset installation finished.")
                        continuation.yield(.finished)
                    case let .failed(_, error):
                        Logger(subsystem: "com.aljaroudi.Muntathir", category: "AssetPacks")
                            .error("Asset download failed: \(String(describing: error), privacy: .public)")
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

#if DEBUG
    import SQLite3

    /// Isolated, deterministic data for UI tests; never substitutes for hosted assets in normal launches.
    enum HadithUITestFixture {
        static func url() throws -> URL {
            let url = URL.applicationSupportDirectory.appending(path: "hadith-ui-fixture-v2.db")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var handle: OpaquePointer?
            guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw HadithDatabaseError.unavailable }
            defer { sqlite3_close(handle) }
            let sql = """
            PRAGMA application_id = 1230262606;
            PRAGMA user_version = 6;
            CREATE TABLE collection(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT, sort_order INTEGER);
            CREATE TABLE book(id TEXT PRIMARY KEY, collection_id TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER, author TEXT, author_ar TEXT);
            CREATE TABLE chapter(id INTEGER PRIMARY KEY, book_id TEXT, chapter_idx INTEGER, file_name TEXT, name_ar TEXT, name_en TEXT);
            CREATE TABLE hadith(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, id_in_book INTEGER, source_id INTEGER, arabic TEXT, english_narrator TEXT, english_text TEXT);
            CREATE TABLE grader(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT);
            CREATE TABLE hadith_grading(id INTEGER PRIMARY KEY, hadith_id INTEGER, grader_id TEXT, grade_ar TEXT, grade_en TEXT, reference_ar TEXT, reference_en TEXT, status TEXT, original_text TEXT);
            CREATE VIRTUAL TABLE hadith_words USING fts5(text, root, lemma, content='', prefix='2 3');
            CREATE VIRTUAL TABLE hadith_fts USING fts5(text, content='', tokenize='trigram');
            CREATE VIEW hadith_english_content AS SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;
            CREATE VIRTUAL TABLE hadith_en USING fts5(text, content='hadith_english_content', content_rowid='id', tokenize='porter unicode61');
            INSERT INTO collection VALUES ('bukhari','كتاب الاختبار','Test book',0);
            INSERT INTO book VALUES ('bukhari','bukhari','كتاب الاختبار','Test book',0,'Test author','مؤلف الاختبار');
            INSERT INTO chapter VALUES (1,'bukhari',0,'1.json','باب الاختبار','Test chapter');
            ALTER TABLE chapter ADD COLUMN hadith_count INTEGER NOT NULL DEFAULT 105;
            WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x < 105)
            INSERT INTO hadith SELECT x,'bukhari',1,x,x,
              '\(String(repeating: "نص تجريبي لاختبار عرض الحديث وحفظ موضع القراءة. ", count: 35))',
              'Test narrator','\(String(repeating: "Sample text for testing reading position and image sharing. ", count: 35))' FROM n;
            INSERT INTO hadith_words(rowid,text) SELECT id,arabic FROM hadith;
            INSERT INTO hadith_fts(rowid,text) SELECT id,arabic FROM hadith;
            INSERT INTO hadith_en(rowid,text) SELECT id,text FROM hadith_english_content;
            """
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                try? FileManager.default.removeItem(at: url)
                throw HadithDatabaseError.unavailable
            }
            return url
        }
    }
#endif
