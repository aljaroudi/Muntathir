import Foundation
@testable import Muntathir
import SwiftData
import Testing

struct ProgressActivityTests {
    @Test func idleTimeBackgroundAndRepeatedFlushes() {
        var clock = ReadingActivityClock()
        clock.resume(at: 100)
        clock.advance(to: 115)
        #expect(clock.drain() == 15)
        clock.advance(to: 500)
        #expect(clock.drain() == 285)
        clock.advance(to: 600)
        #expect(clock.drain() == 0)
        clock.interact(at: 600)
        clock.pause(at: 620)
        #expect(clock.drain() == 20)
        clock.advance(to: 1000)
        #expect(clock.drain() == 0)
        clock.resume(at: 1000)
        clock.pause(at: 1005)
        #expect(clock.drain() == 5)
        #expect(clock.drain() == 0)
    }

    @Test func interactionsExtendReadingWithoutCountingIdleGap() {
        var clock = ReadingActivityClock()
        clock.resume(at: 0)
        clock.interact(at: 200)
        clock.interact(at: 400)
        clock.pause(at: 1000)
        #expect(clock.drain() == 700)
    }

    @Test func duplicateAndOutOfOrderSyncUsesLargestSessionSnapshot() {
        let id = UUID()
        let old = ProgressActivity(id: id, kind: .tasbih, amount: 10)
        let latest = ProgressActivity(id: id, kind: .tasbih, amount: 20)
        let otherSession = ProgressActivity(kind: .tasbih, amount: 4)
        let reading = ProgressActivity(kind: .quranReading, amount: 90)
        for records in [[old, latest, otherSession, reading, latest], [latest, old, reading, otherSession]] {
            let totals = ProgressActivity.totals(records)
            #expect(totals[.tasbih] == 24)
            #expect(totals[.quranReading] == 90)
            #expect(totals[.hadithReading] == nil)
        }
        #expect(ProgressActivity.totals([.init(kind: .tasbih, amount: -1), .init(kind: .tasbih, amount: 1.5), .init(kind: .hadithReading, amount: .infinity)]).isEmpty)
    }

    @MainActor @Test func activityPersistenceRetryAndSessionUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(schema: Schema([PrayerHistoryRecord.self, ProgressActivityRecord.self]), url: directory.appending(path: "history.store"), cloudKitDatabase: .none)
        var fail = true
        let store = ProgressStore(configuration: configuration) { context in
            if fail {
                throw CocoaError(.fileWriteUnknown)
            }
            try context.save()
        }
        let id = UUID()
        store.saveActivity(.init(id: id, kind: .tasbih, amount: 1))
        store.saveActivity(.init(id: id, kind: .tasbih, amount: 2))
        #expect(store.pendingActivities.count == 1)
        #expect(store.pendingActivities.first?.amount == 2)
        #expect(store.activities.isEmpty)
        fail = false
        store.retry()
        store.saveActivity(.init(id: id, kind: .tasbih, amount: 3))
        store.saveActivity(.init(id: id, kind: .tasbih, amount: 1))
        #expect(store.activities.count == 1)
        #expect(ProgressActivity.totals(store.activities)[.tasbih] == 3)
        #expect(!store.unavailable)
        #expect(store.pendingActivities.isEmpty)
        let reopened = ProgressStore(configuration: configuration)
        #expect(ProgressActivity.totals(reopened.activities)[.tasbih] == 3)
    }

    @MainActor @Test func addingActivitySchemaPreservesExistingPrayers() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let record = PrayerProgress.snapshot(prayer: .fajr, at: .now, location: nil, method: .jafari)
        do {
            let old = try ModelContainer(for: PrayerHistoryRecord.self, configurations: ModelConfiguration(schema: Schema([PrayerHistoryRecord.self]), url: url, cloudKitDatabase: .none))
            try old.mainContext.insert(PrayerHistoryRecord(record))
            try old.mainContext.save()
        }
        let store = ProgressStore(configuration: ModelConfiguration(schema: Schema([PrayerHistoryRecord.self, ProgressActivityRecord.self]), url: url, cloudKitDatabase: .none))
        #expect(store.records == [record])
        #expect(store.activities.isEmpty)
        #expect(!store.unavailable)
    }
}
