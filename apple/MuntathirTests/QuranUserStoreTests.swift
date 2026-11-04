import Foundation
@testable import Muntathir
import SwiftData
import Testing

@MainActor struct QuranUserStoreTests {
    private func configuration(url: URL? = nil) -> ModelConfiguration {
        let schema = Schema([HighlightRecord.self])
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
    }

    @Test func multipleHighlightsKeepNotesAndSeparateQuranFromHadith() throws {
        let store = QuranUserStore(configuration: configuration(), installationID: "A")
        var first = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "verse", reference: "1:1")
        first.note = "A private thought"
        var second = first
        second.id = UUID().uuidString
        second.color = .green
        second.note = "Another thought"
        var hadith = first
        hadith.id = UUID().uuidString
        hadith.isHadith = true
        try store.save(first)
        try store.save(second)
        try store.save(hadith)
        #expect(store.highlights(for: "1:1").count == 2)
        #expect(store.highlights(for: "1:1", isHadith: true).count == 1)
        try store.delete(first)
        #expect(store.highlights(for: "1:1").map(\.note) == ["Another thought"])
        let rows = try #require(store.container).mainContext.fetch(FetchDescriptor<HighlightRecord>())
        #expect(rows.contains { $0.highlightID == first.id && $0.isTombstone })
    }

    @Test func syncUsesStableTieBreakAndLocalEditsBeatImportedState() throws {
        let store = QuranUserStore(configuration: configuration(), installationID: "A")
        let context = try #require(store.container?.mainContext)
        var value = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "text", reference: "1:1")
        for id in ["a", "z"] {
            let row = HighlightRecord(highlightID: value.id, installationID: id)
            row.recordID = id
            value.note = id
            row.payload = try JSONEncoder().encode(value)
            row.modifiedAt = Date(timeIntervalSince1970: 100)
            context.insert(row)
        }
        try context.save()
        let rows = try context.fetch(FetchDescriptor<HighlightRecord>()).map(HighlightSnapshot.init)
        store.receive(rows)
        #expect(store.highlights.first?.note == "z")
        #expect(HighlightSnapshot.winners(rows) == HighlightSnapshot.winners(rows.reversed()))
        value.note = "edited"
        try store.save(value, now: Date(timeIntervalSince1970: 50))
        #expect(store.highlights.first?.note == "edited")
        #expect(try #require(store.highlights.first).modifiedAt > Date(timeIntervalSince1970: 100))
        try store.delete(value, now: Date(timeIntervalSince1970: 50))
        #expect(store.highlights.isEmpty)
    }

    @Test func failedSaveAndDeleteRollBackAndCanRetry() throws {
        var fail = false
        let store = QuranUserStore(configuration: configuration(), installationID: "A") { context in
            if fail {
                throw QuranUserStoreError.unavailable
            }
            try context.save()
        }
        var value = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "text", reference: "1:1")
        value.note = "saved"
        try store.save(value)
        fail = true
        value.note = "draft"
        #expect(throws: QuranUserStoreError.self) { try store.save(value) }
        #expect(store.highlights.first?.note == "saved")
        #expect(throws: QuranUserStoreError.self) { try store.delete(value) }
        #expect(store.highlights.count == 1)
        fail = false
        try store.save(value)
        #expect(store.highlights.first?.note == "draft")
    }

    @Test func highlightsSurviveReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = configuration(url: directory.appending(path: "highlights.store"))
        let value = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "text", reference: "1:1")
        do { let store = QuranUserStore(configuration: config, installationID: "A"); try store.save(value) }
        let reopened = QuranUserStore(configuration: config, installationID: "A")
        #expect(reopened.highlights.first?.id == value.id)
    }

    @Test func rangesPreserveRepeatedArabicTextAndRejectChangedSource() throws {
        let text = "بِسْمِ الله بِسْمِ الله"
        let range = (text as NSString).range(of: "بِسْمِ", options: .backwards)
        let selection = try #require(HighlightRange(range, in: text))
        let value = ReadingHighlight(source: "1:1", isHadith: false, block: "arabic", ranges: [selection], excerpt: selection.quote, reference: "1:1")
        #expect(value.ranges(in: text, block: "arabic") == [range])
        #expect(value.ranges(in: text, block: "en.qarai").isEmpty)
        #expect(!value.isAvailable(in: ["arabic": "changed"]))
        #expect(HighlightRange(NSRange(location: 999, length: 1), in: text) == nil)
    }

    @Test func multipleSelectionRangesAndWholeItemScope() throws {
        let text = "Arabic English العربية"
        let ranges = try [NSRange(location: 0, length: 6), (text as NSString).range(of: "العربية")].map { try #require(HighlightRange($0, in: text)) }
        let partial = ReadingHighlight(source: "source", isHadith: true, block: "english", ranges: ranges, excerpt: "selection", reference: "source")
        #expect(partial.ranges(in: text, block: "english").count == 2)
        let whole = ReadingHighlight(source: "source", isHadith: true, excerpt: text, reference: "source")
        for block in ["arabic", "english", "englishNarrator", "en.qarai"] {
            #expect(whole.ranges(in: text, block: block) == [NSRange(location: 0, length: text.utf16.count)])
        }
    }
}
