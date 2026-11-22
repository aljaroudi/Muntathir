import Foundation
@testable import Muntathir
import SwiftData
import Testing

struct PrayerProgressTests {
    private let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
    private let day = Date(timeIntervalSince1970: 1_794_520_800)

    @Test func selection() {
        #expect(PrayerProgress.prayers.map(PrayerProgress.rakaat(for:)) == [2, 4, 4, 3, 4])
        #expect(PrayerProgress.followUp(after: .dhuhr) == .asr)
        #expect(PrayerProgress.followUp(after: .maghrib) == .isha)
        #expect([PrayerName.fajr, .asr, .isha].allSatisfy { PrayerProgress.followUp(after: $0) == nil })
        #expect(AppTool.normalized(["prayerProgress"]) == [.prayerProgress])
        #expect(AppTool.groups.flatMap(\.tools).contains(.prayerProgress))
    }

    @Test func suggestionFollowsOnTimeWindowsAndHistory() throws {
        let times = PrayerCalculator.times(on: day, location: location, method: .jafari)
        func time(_ name: PrayerName) throws -> Date {
            try #require(times.first { $0.name == name }?.date)
        }
        func suggestion(at date: Date, completed: [PrayerCompletion] = []) -> PrayerName? {
            PrayerProgress.suggestedPrayer(at: date, location: location, method: .jafari, completed: completed)
        }
        let dhuhr = try time(.dhuhr).addingTimeInterval(60)
        #expect(suggestion(at: dhuhr) == .dhuhr)
        let prayedDhuhr = PrayerProgress.snapshot(prayer: .dhuhr, at: dhuhr, location: location, method: .jafari)
        #expect(suggestion(at: dhuhr, completed: [prayedDhuhr]) == .asr)
        let prayedAsr = PrayerProgress.snapshot(prayer: .asr, at: dhuhr, location: location, method: .jafari)
        #expect(suggestion(at: dhuhr, completed: [prayedDhuhr, prayedAsr]) == .maghrib)
        #expect(try suggestion(at: time(.sunrise).addingTimeInterval(60)) == .dhuhr)
        #expect(try suggestion(at: time(.maghrib).addingTimeInterval(60)) == .maghrib)
        #expect(try suggestion(at: time(.fajr).addingTimeInterval(-60)) == .fajr)
        #expect(try suggestion(at: time(.midnight).addingTimeInterval(60)) == .fajr)
        #expect(PrayerProgress.suggestedPrayer(at: dhuhr, location: nil, method: .jafari, completed: []) == nil)
    }

    @Test(arguments: PrayerProgress.prayers, PrayerMethod.allCases)
    func boundaries(prayer: PrayerName, method: PrayerMethod) throws {
        let times = PrayerCalculator.times(on: day, location: location, method: method)
        let startName: PrayerName = [.asr: .dhuhr, .isha: .maghrib][prayer] ?? prayer
        let start = try #require(times.first { $0.name == startName }?.date)
        let endName: PrayerName = prayer == .fajr ? .sunrise : ([.dhuhr, .asr].contains(prayer) ? .sunset : .midnight)
        let end = try #require(times.first { $0.name == endName }?.date)
        for (date, expected) in [
            (start.addingTimeInterval(-1), PrayerTiming.outsideTime),
            (start, .onTime),
            (start.addingTimeInterval(1), .onTime),
            (end.addingTimeInterval(-1), .onTime),
            (end, .outsideTime),
        ] {
            let record = PrayerProgress.snapshot(prayer: prayer, at: date, location: location, method: method)
            #expect(record.timing == expected)
            #expect(record.athan == start)
            #expect(record.deadline == end)
        }
    }

    @Test func previousEveningAndMissingTiming() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let midnight = calendar.startOfDay(for: day)
        let record = PrayerProgress.snapshot(prayer: .isha, at: midnight, location: location, method: .jafari)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: midnight))
        #expect(record.prayerDay == PrayerProgress.dayKey(yesterday, timeZone: location.timeZone))
        let previousTimes = PrayerCalculator.times(on: yesterday, location: location, method: .jafari)
        let previousMaghrib = try #require(previousTimes.first { $0.name == .maghrib }?.date)
        #expect(record.athan == previousMaghrib)
        let missing = PrayerProgress.snapshot(prayer: .fajr, at: day, location: nil, method: .jafari, fallbackTimeZone: .gmt)
        #expect(missing.timing == .unavailable)
        #expect(missing.timeZoneID == "GMT")
        let unavailable = PrayerProgress.snapshot(prayer: .fajr, at: day, location: location, method: .jafari, calculate: { _, _, _ in [] })
        #expect(unavailable.timing == .unavailable)
    }

    @Test(arguments: [("2026-11-01T06:30:00Z", "2026-10-31"), ("2026-03-08T07:30:00Z", "2026-03-07")])
    func dstAndTravelKeepPrayerDay(instant: String, expectedDay: String) throws {
        let newYork = SavedLocation(latitude: 40.7128, longitude: -74.006, name: "New York", countryCode: "US", timeZoneID: "America/New_York")
        let date = try #require(ISO8601DateFormatter().date(from: instant))
        let record = PrayerProgress.snapshot(prayer: .isha, at: date, location: newYork, method: .jafari)
        #expect(record.prayerDay == expectedDay)
        #expect(record.timeZoneID == "America/New_York")
        let decoded = try JSONDecoder().decode(PrayerCompletion.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(PrayerProgress.days(for: .isha, in: [decoded]).keys.contains(expectedDay))
    }

    @Test func completionUsesCalibrationAndOnlySavesOnce() throws {
        let times = PrayerCalculator.times(on: day, location: location, method: .jafari)
        let sunrise = try #require(times.first { $0.name == .sunrise }?.date)
        let ready = sunrise.addingTimeInterval(-60)
        let snapshot = PrayerProgress.snapshot(prayer: .fajr, at: ready, location: location, method: .jafari)
        var session = PrayerSessionRecording()
        #expect(session.update(calibrated: false, complete: false, failed: false, at: ready) { snapshot } == nil)
        #expect(session.snapshot == nil)
        #expect(session.update(calibrated: true, complete: false, failed: false, at: ready) { snapshot } == nil)
        let completion = try #require(session.update(calibrated: true, complete: true, failed: false, at: sunrise) { nil })
        #expect(completion.timing == .onTime)
        #expect(completion.startedAt == ready)
        #expect(completion.completedAt == sunrise)
        #expect(session.update(calibrated: true, complete: true, failed: false, at: sunrise) { snapshot } == nil)
        var failed = PrayerSessionRecording()
        #expect(failed.update(calibrated: true, complete: true, failed: true, at: day) { snapshot } == nil)
        #expect(failed.update(calibrated: true, complete: true, failed: false, at: day) { snapshot } == nil)
        var other = PrayerSessionRecording()
        #expect(other.update(calibrated: true, complete: true, failed: false, at: day) { nil } == nil)
    }

    @Test func aggregationIsPerPrayerDateAndPositiveWins() throws {
        let times = PrayerCalculator.times(on: day, location: location, method: .jafari)
        let fajr = try #require(times.first { $0.name == .fajr }?.date)
        let sunrise = try #require(times.first { $0.name == .sunrise }?.date)
        let onTime = PrayerProgress.snapshot(prayer: .fajr, at: fajr, location: location, method: .jafari)
        let late = PrayerProgress.snapshot(prayer: .fajr, at: sunrise, location: location, method: .jafari)
        let days = PrayerProgress.days(for: .fajr, in: [late, onTime, onTime])
        #expect(days.count == 1)
        #expect(days[onTime.prayerDay] == .onTime)
        #expect(PrayerProgress.days(for: .isha, in: [onTime]).isEmpty)
    }

    @MainActor @Test func persistenceRetryAndDuplicateSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(schema: Schema([PrayerHistoryRecord.self, ProgressActivityRecord.self]), url: directory.appending(path: "history.store"), cloudKitDatabase: .none)
        var shouldFail = true
        let store = ProgressStore(configuration: configuration) { context in
            if shouldFail {
                throw CocoaError(.fileWriteUnknown)
            }
            try context.save()
        }
        let record = PrayerProgress.snapshot(prayer: .fajr, at: day, location: location, method: .jafari)
        store.save(record)
        #expect(store.unavailable)
        #expect(store.records.isEmpty)
        #expect(store.pending.count == 1)
        shouldFail = false
        store.retry()
        store.save(record)
        #expect(!store.unavailable)
        #expect(store.pending.isEmpty)
        #expect(store.records == [record])
        let reopened = ProgressStore(configuration: configuration)
        #expect(reopened.records == [record])
        let payload = try JSONEncoder().encode(record)
        reopened.receive([payload, payload])
        #expect(PrayerProgress.days(for: .fajr, in: reopened.records).count == 1)
    }
}
