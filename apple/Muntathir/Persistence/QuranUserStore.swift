import Foundation
import Observation
import SwiftData

@MainActor @Observable final class QuranUserStore {
    private(set) var container: ModelContainer?
    private(set) var highlights: [ReadingHighlight] = []
    private(set) var bookmarks: [ReadingBookmark] = []
    private(set) var unavailable = false
    @ObservationIgnored private let configuration: ModelConfiguration
    @ObservationIgnored private var installationID: String
    @ObservationIgnored private let saveContext: (ModelContext) throws -> Void

    init(configuration: ModelConfiguration, installationID: String, saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.configuration = configuration
        self.installationID = installationID
        self.saveContext = saveContext
        reopen()
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: HighlightRecord.self, BookmarkRecord.self, configurations: configuration)
    }

    static func application() -> QuranUserStore {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        let schema = Schema([HighlightRecord.self, BookmarkRecord.self])
        if testing {
            let directory = URL.applicationSupportDirectory.appending(path: "HighlightsUITests", directoryHint: .isDirectory)
            // Only an explicitly requested UI-test reset removes this isolated test store.
            if !arguments.contains("--ui-testing-preserve-state") {
                try? FileManager.default.removeItem(at: directory)
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = QuranUserStore(configuration: ModelConfiguration("HighlightsUITests", schema: schema, url: directory.appending(path: "highlights.store"), cloudKitDatabase: .none), installationID: "ui-tests") { context in
                if arguments.contains("--ui-testing-quran-save-failure") {
                    throw QuranUserStoreError.unavailable
                }
                try context.save()
            }
            if arguments.contains("--ui-testing-legacy-highlights"), !arguments.contains("--ui-testing-preserve-state") {
                do {
                    for note in ["First note", "Second note"] {
                        var highlight = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "Legacy whole-verse highlight", reference: "1:1")
                        highlight.note = note
                        highlight.color = .green
                        try store.save(highlight)
                    }
                } catch { assertionFailure("Unable to seed legacy highlights: \(error)") }
            }
            return store
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return QuranUserStore(configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none), installationID: "unit-tests")
        }
        return QuranUserStore(configuration: ModelConfiguration("ReadingHighlights", schema: schema, cloudKitDatabase: .private("iCloud.com.aljaroudi.Muntathir")), installationID: "")
    }

    static func localInstallationID(directory: URL = URL.applicationSupportDirectory.appending(path: "QuranIdentity", directoryHint: .isDirectory)) throws -> String {
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A restored backup must not let two devices edit the same installation's sync records.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let file = directory.appending(path: "installation-id")
        if FileManager.default.fileExists(atPath: file.path) {
            let value = try String(contentsOf: file, encoding: .utf8)
            guard UUID(uuidString: value) != nil else { throw QuranUserStoreError.unavailable }
            return value
        }
        let value = UUID().uuidString
        try Data(value.utf8).write(to: file, options: .atomic)
        return value
    }

    func reopen() {
        do {
            if installationID.isEmpty {
                installationID = try Self.localInstallationID()
            }
            let opened = try Self.makeContainer(configuration: configuration)
            opened.mainContext.autosaveEnabled = false
            let rows = try opened.mainContext.fetch(FetchDescriptor<HighlightRecord>())
            container = opened
            receive(rows.map(HighlightSnapshot.init))
            try receiveBookmarks(opened.mainContext.fetch(FetchDescriptor<BookmarkRecord>()).map(BookmarkSnapshot.init))
            unavailable = false
        } catch {
            container = nil
            unavailable = true
        }
    }

    func receive(_ rows: [HighlightSnapshot]) {
        highlights = HighlightSnapshot.winners(rows).values.filter { !$0.isTombstone }.compactMap {
            try? JSONDecoder().decode(ReadingHighlight.self, from: $0.payload)
        }.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id > $1.id : $0.modifiedAt > $1.modifiedAt }
    }

    func receiveBookmarks(_ rows: [BookmarkSnapshot]) {
        bookmarks = BookmarkSnapshot.winners(rows).values.filter { !$0.isTombstone }.compactMap {
            try? JSONDecoder().decode(ReadingBookmark.self, from: $0.payload)
        }.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id > $1.id : $0.modifiedAt > $1.modifiedAt }
    }

    func bookmark(for source: String, isHadith: Bool = false) -> ReadingBookmark? {
        bookmarks.first { $0.source == source && $0.isHadith == isHadith }
    }

    func save(_ bookmark: ReadingBookmark, now: Date = .now) throws {
        guard !bookmark.source.isEmpty else { throw QuranUserStoreError.invalidBookmark }
        try update(bookmark, deleted: false, now: now)
    }

    func delete(_ bookmark: ReadingBookmark, now: Date = .now) throws {
        try update(bookmark, deleted: true, now: now)
    }

    private func update(_ bookmark: ReadingBookmark, deleted: Bool, now: Date) throws {
        guard let context = container?.mainContext else { throw QuranUserStoreError.unavailable }
        do {
            let rows = try context.fetch(FetchDescriptor<BookmarkRecord>())
            let matching = rows.filter { $0.bookmarkID == bookmark.id }
            let winner = BookmarkSnapshot.winners(matching.map(BookmarkSnapshot.init))[bookmark.id]
            let local = matching.filter { $0.installationID == installationID }.sorted { $0.recordID > $1.recordID }.first
            let row = local ?? BookmarkRecord(bookmarkID: bookmark.id, installationID: installationID)
            if local == nil {
                context.insert(row)
            }
            var value = bookmark
            if let winner, !winner.isTombstone,
               let existing = try? JSONDecoder().decode(ReadingBookmark.self, from: winner.payload)
            {
                value.createdAt = existing.createdAt
            }
            value.modifiedAt = max(now, (winner?.modifiedAt ?? .distantPast).addingTimeInterval(0.001))
            row.payload = try JSONEncoder().encode(value)
            row.modifiedAt = value.modifiedAt
            row.isTombstone = deleted
            try saveContext(context)
            try receiveBookmarks(context.fetch(FetchDescriptor<BookmarkRecord>()).map(BookmarkSnapshot.init))
        } catch {
            context.rollback()
            if let rows = try? context.fetch(FetchDescriptor<BookmarkRecord>()) {
                receiveBookmarks(rows.map(BookmarkSnapshot.init))
            }
            throw error
        }
    }

    func highlights(for source: String, isHadith: Bool = false) -> [ReadingHighlight] {
        highlights.filter { $0.source == source && $0.isHadith == isHadith }
    }

    func save(_ highlight: ReadingHighlight, now: Date = .now) throws {
        guard !highlight.source.isEmpty, highlight.block == nil || !highlight.ranges.isEmpty else { throw QuranUserStoreError.invalidHighlight }
        try update(highlight, deleted: false, now: now)
    }

    func delete(_ highlight: ReadingHighlight, now: Date = .now) throws {
        try update(highlight, deleted: true, now: now)
    }

    private func update(_ highlight: ReadingHighlight, deleted: Bool, now: Date) throws {
        guard let context = container?.mainContext else { throw QuranUserStoreError.unavailable }
        do {
            // Imported state may have changed since the editor opened.
            let rows = try context.fetch(FetchDescriptor<HighlightRecord>())
            let matching = rows.filter { $0.highlightID == highlight.id }
            let winner = HighlightSnapshot.winners(matching.map(HighlightSnapshot.init))[highlight.id]
            let local = matching.filter { $0.installationID == installationID }.sorted { $0.recordID > $1.recordID }.first
            let row = local ?? HighlightRecord(highlightID: highlight.id, installationID: installationID)
            if local == nil {
                context.insert(row)
            }
            var value = highlight
            value.modifiedAt = max(now, (winner?.modifiedAt ?? .distantPast).addingTimeInterval(0.001))
            value.note = value.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value.note
            row.payload = try JSONEncoder().encode(value)
            row.modifiedAt = value.modifiedAt
            row.isTombstone = deleted
            try saveContext(context)
            try receive(context.fetch(FetchDescriptor<HighlightRecord>()).map(HighlightSnapshot.init))
        } catch {
            context.rollback()
            if let rows = try? context.fetch(FetchDescriptor<HighlightRecord>()) {
                receive(rows.map(HighlightSnapshot.init))
            }
            throw error
        }
    }
}

enum QuranUserStoreError: Error { case unavailable, invalidHighlight, invalidBookmark }
