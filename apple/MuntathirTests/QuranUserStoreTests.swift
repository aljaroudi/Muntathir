import Foundation
@testable import Muntathir
import SwiftData
import Testing

@MainActor struct QuranUserStoreTests {
    private func configuration(url: URL? = nil) -> ModelConfiguration {
        let schema = Schema(versionedSchema: QuranUserSchemaV1.self)
        if let url {
            return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }

    @Test func installationIdentityPersistsAndIsExcludedFromBackups() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try QuranUserStore.localInstallationID(directory: directory)
        #expect(try QuranUserStore.localInstallationID(directory: directory) == first)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let other = try QuranUserStore.localInstallationID(directory: directory.appending(path: "another-installation"))
        #expect(other != first)
    }

    @Test func favoritesAndNotesPersistIndependentlyAndKeepDeletionTimestamps() throws {
        let store = QuranUserStore(configuration: configuration(), installationID: "A")
        #expect(store.unavailable == false)
        try store.setFavorite(true, for: "2:255")
        try store.setNote("A private thought", for: "2:255")
        #expect(store.state(for: "2:255").isFavorite)
        #expect(store.state(for: "2:255").note == "A private thought")
        try store.setFavorite(false, for: "2:255")
        #expect(store.state(for: "2:255").note == "A private thought")
        try store.setNote("  \n", for: "2:255")
        #expect(store.state(for: "2:255").isFavorite == false)
        #expect(store.state(for: "2:255").note.isEmpty)
        let context = try #require(store.container?.mainContext)
        let row = try #require(try context.fetch(FetchDescriptor<QuranAnnotation>()).first)
        #expect(row.noteModifiedAt > Date(timeIntervalSince1970: 0))
        #expect(row.favoriteModifiedAt > Date(timeIntervalSince1970: 0))
        #expect(try context.fetchCount(FetchDescriptor<QuranAnnotation>()) == 1)
    }

    @Test func offlineChangesResolveByFieldAndOrderDoesNotMatter() {
        let first = QuranAnnotation(verseID: "2:255", installationID: "A")
        first.recordID = "a"
        first.isFavorite = true
        first.favoriteModifiedAt = Date(timeIntervalSince1970: 10)
        first.note = "Old note"
        first.noteModifiedAt = Date(timeIntervalSince1970: 5)
        let second = QuranAnnotation(verseID: "2:255", installationID: "B")
        second.recordID = "b"
        second.note = "New note"
        second.noteModifiedAt = Date(timeIntervalSince1970: 20)
        let rows = [first, second].map(QuranAnnotationSnapshot.init)
        let state = QuranVerseState.resolve(rows)["2:255"]
        #expect(state?.isFavorite == true)
        #expect(state?.note == "New note")
        #expect(QuranVerseState.resolve(rows) == QuranVerseState.resolve(rows.reversed()))
        // Deletions remain newer than stale offline edits, without deleting the record.
        second.isFavorite = false
        second.favoriteModifiedAt = Date(timeIntervalSince1970: 30)
        second.note = ""
        second.noteModifiedAt = Date(timeIntervalSince1970: 30)
        let deleted = QuranVerseState.resolve([second, first].map(QuranAnnotationSnapshot.init))["2:255"]
        #expect(deleted?.isFavorite == false)
        #expect(deleted?.note.isEmpty == true)
    }

    @Test func duplicateRecordsUseStableTieBreakAndLocalEditsBeatImportedState() throws {
        let store = QuranUserStore(configuration: configuration(), installationID: "A")
        let context = try #require(store.container?.mainContext)
        for id in ["a", "z"] {
            let row = QuranAnnotation(verseID: "1:1", installationID: "A")
            row.recordID = id
            row.note = id
            row.noteModifiedAt = Date(timeIntervalSince1970: 100)
            context.insert(row)
        }
        try context.save()
        try store.receive(context.fetch(FetchDescriptor<QuranAnnotation>()).map(QuranAnnotationSnapshot.init))
        #expect(store.state(for: "1:1").note == "z")
        try store.setNote("edited", for: "1:1", now: Date(timeIntervalSince1970: 50))
        #expect(store.state(for: "1:1").note == "edited")
        #expect(try context.fetchCount(FetchDescriptor<QuranAnnotation>()) == 2)
    }

    @Test func failedSaveRollsBackAndCanRetry() throws {
        var fail = false
        let store = QuranUserStore(configuration: configuration(), installationID: "A") { context in
            if fail {
                throw QuranUserStoreError.unavailable
            }
            try context.save()
        }
        try store.setNote("saved", for: "1:1")
        fail = true
        #expect(throws: QuranUserStoreError.self) { try store.setNote("draft", for: "1:1") }
        #expect(store.state(for: "1:1").note == "saved")
        #expect(throws: QuranUserStoreError.self) { try store.setFavorite(true, for: "2:255") }
        #expect(store.state(for: "2:255").isFavorite == false)
        fail = false
        try store.setNote("draft", for: "1:1")
        #expect(store.state(for: "1:1").note == "draft")
    }

    @Test func v1DiskFixtureReopensThroughTheCurrentMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = configuration(url: directory.appending(path: "v1.store"))
        // Generate using the frozen V1 schema, independent of future current-schema aliases.
        do {
            let container = try ModelContainer(for: Schema(versionedSchema: QuranUserSchemaV1.self), configurations: [config])
            let row = QuranUserSchemaV1.Annotation(verseID: "2:255", installationID: "fixture")
            row.isFavorite = true
            row.favoriteModifiedAt = Date(timeIntervalSince1970: 10)
            row.note = "V1 note"
            row.noteModifiedAt = Date(timeIntervalSince1970: 20)
            container.mainContext.insert(row)
            try container.mainContext.save()
        }
        let reopened = QuranUserStore(configuration: config, installationID: "new-installation")
        #expect(reopened.unavailable == false)
        #expect(reopened.state(for: "2:255").isFavorite)
        #expect(reopened.state(for: "2:255").note == "V1 note")
        try reopened.setNote("Updated note", for: "2:255")
        let again = QuranUserStore(configuration: config, installationID: "new-installation")
        #expect(again.state(for: "2:255").note == "Updated note")
        #expect(again.state(for: "2:255").isFavorite)
    }

    @Test func invalidStoreIsNotErasedOrReplacedWithMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "broken.store")
        let original = Data("not a store".utf8)
        try original.write(to: url)
        let store = QuranUserStore(configuration: configuration(url: url), installationID: "A")
        #expect(store.container == nil)
        #expect(store.unavailable)
        #expect(try Data(contentsOf: url) == original)
        #expect(throws: QuranUserStoreError.self) { try store.setNote("draft", for: "1:1") }
    }
}
