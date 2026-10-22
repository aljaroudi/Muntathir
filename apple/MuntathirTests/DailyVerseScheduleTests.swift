import Foundation
@testable import Muntathir
import Testing

struct DailyVerseScheduleTests {
    private func entries() -> [DailyVerseSchedule.Entry] {
        (1 ... 12).flatMap { month in
            (1 ... 30).map { day in
                DailyVerseSchedule.Entry(hijriMonth: month, hijriDay: day, verseID: (month - 1) * 30 + day)
            }
        }
    }

    @Test func completeScheduleIncludesEveryPossibleDate() throws {
        let schedule = try DailyVerseSchedule(entries: entries())
        for month in 1 ... 12 {
            for day in 1 ... 30 {
                let resolved = ResolvedDay(month: .init(year: 1448, month: month), day: day, provenance: .calculated, sourceID: nil)
                #expect(schedule.verseID(on: resolved) == (month - 1) * 30 + day)
            }
        }
    }

    @Test func incompleteDuplicateAndInvalidSchedulesAreRejected() throws {
        let all = entries()
        #expect(throws: DailyVerseSchedule.ValidationError.self) { try DailyVerseSchedule(entries: Array(all.dropLast())) }
        var duplicate = all
        duplicate[359] = all[0]
        #expect(throws: DailyVerseSchedule.ValidationError.self) { try DailyVerseSchedule(entries: duplicate) }
        for invalid in [
            DailyVerseSchedule.Entry(hijriMonth: 13, hijriDay: 1, verseID: 1),
            .init(hijriMonth: 1, hijriDay: 31, verseID: 1),
            .init(hijriMonth: 1, hijriDay: 1, verseID: 0),
            .init(hijriMonth: 1, hijriDay: 1, verseID: -1),
        ] {
            var invalidEntries = all
            invalidEntries[0] = invalid
            #expect(throws: DailyVerseSchedule.ValidationError.self) { try DailyVerseSchedule(entries: invalidEntries) }
        }
        let missingID = Data("{\"entries\":[{\"hijriMonth\":1,\"hijriDay\":1}]}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DailyVerseSchedule.self, from: missingID) }
    }

    @Test func correctionAndLocationMidnightSelectTheSameVerseForAppAndWidget() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let baseline = try CalendarEngine(timeZone: zone)
        let month = HijriMonth(year: 1448, month: 5)
        let start = baseline.addingDays(1, to: baseline.baselineStart(month))
        let correction = MonthCorrection(month: month, start: CivilDate(start, in: zone), provenance: .manual, sourceID: nil)
        let appEngine = try CalendarEngine(timeZone: zone, manual: [correction])
        let widgetEngine = WidgetCalendarSettings(timeZoneID: zone.identifier, manual: [correction]).engine
        let schedule = try DailyVerseSchedule(entries: entries())
        let nextMidnight = appEngine.addingDays(1, to: start)
        #expect(appEngine.resolve(start).day == 1)
        #expect(baseline.resolve(start).day == 2)
        #expect(schedule.verseID(on: appEngine.resolve(nextMidnight.addingTimeInterval(-1))) == 121)
        #expect(schedule.verseID(on: appEngine.resolve(nextMidnight)) == 122)
        for date in [start, nextMidnight.addingTimeInterval(-1), nextMidnight] {
            #expect(schedule.verseID(on: appEngine.resolve(date)) == schedule.verseID(on: widgetEngine.resolve(date)))
        }
    }

    @Test(arguments: ["Asia/Riyadh", "America/New_York"])
    func preloadedVersesRollOverForSevenDaysWithoutOpeningApp(zoneID: String) throws {
        let settings = WidgetCalendarSettings(timeZoneID: zoneID)
        let start = try #require(CivilDate(year: 2026, month: 3, day: 7).date(in: settings.zone)).addingTimeInterval(12 * 3600)
        let library = ContentLibrary()
        let dates = settings.timelineDates(from: start)
        #expect(dates.count == 8)
        for date in dates.dropFirst() {
            #expect(settings.engine.gregorian.component(.hour, from: date) == 0)
            #expect(library.verse(on: date.addingTimeInterval(-1), engine: settings.engine)?.id != library.verse(on: date, engine: settings.engine)?.id)
        }
        let renewed = try settings.timelineDates(from: #require(dates.last))
        #expect(renewed.count == 8)
        #expect(try #require(renewed.last) > #require(dates.last))
    }

    @Test func databaseContainsTheCompleteBilingualQuranAndIsReadOnly() throws {
        let url = try #require(Bundle.main.url(forResource: "db", withExtension: "db"))
        let before = try Data(contentsOf: url)
        let verses = QuranDatabase(url: url).verses(ids: Set(1 ... 6236))
        #expect(verses.count == 6236)
        #expect(verses[1]?.id == "1:1")
        #expect(verses[6236]?.id == "114:6")
        #expect(verses.values.allSatisfy { !$0.text.isEmpty && $0.english?.isEmpty == false })
        #expect(try Data(contentsOf: url) == before)
        #expect(QuranDatabase(url: url).verses(ids: [0, -1, 6237]).isEmpty)
    }

    @Test func missingOrMalformedDatabaseDoesNotCreateFilesOrCrash() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(QuranDatabase(url: nil).verses(ids: [1]).isEmpty)
        #expect(QuranDatabase(url: url).verses(ids: [1]).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try Data("not a database".utf8).write(to: url)
        #expect(QuranDatabase(url: url).verses(ids: [1]).isEmpty)
    }

    @Test func appAndWidgetBundleIdenticalDatabaseAndDailyReferences() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appendingPathComponent("MuntathirWidgets.appex")))
        let appVerses = ContentLibrary().verses
        let widgetVerses = ContentLibrary(bundle: widget).verses
        #expect(appVerses.count == 31)
        #expect(appVerses.map(\.id) == widgetVerses.map(\.id))
        #expect(appVerses.map(\.text) == widgetVerses.map(\.text))
        #expect(appVerses.map(\.english) == widgetVerses.map(\.english))
        #expect(appVerses.allSatisfy { $0.english?.isEmpty == false })
        let appDB = try #require(Bundle.main.url(forResource: "db", withExtension: "db"))
        let widgetDB = try #require(widget.url(forResource: "db", withExtension: "db"))
        #expect(try Data(contentsOf: appDB) == Data(contentsOf: widgetDB))
    }

    @Test func completeDatasetActivatesAndInvalidReferenceNeverFallsBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.daily-verses"], format: .xml, options: 0)
        try info.write(to: folder.appendingPathComponent("Info.plist"))
        let source = try #require(Bundle.main.url(forResource: "db", withExtension: "db"))
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("db.db"))
        try Data("[2373]".utf8).write(to: folder.appendingPathComponent("quran-daily-ids.json"))
        let resource = folder.appendingPathComponent("quran-daily.json")
        func write(_ entries: [DailyVerseSchedule.Entry]) throws {
            try (Data("{\"entries\":".utf8) + JSONEncoder().encode(entries) + Data("}".utf8)).write(to: resource)
        }
        try write(entries())
        let bundle = try #require(Bundle(url: folder))
        let engine = try CalendarEngine(timeZone: .gmt)
        let date = engine.start(of: .init(year: 1448, month: 1))
        #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine)?.id == "1:1")
        var invalid = entries()
        invalid[0] = .init(hijriMonth: 1, hijriDay: 1, verseID: 99999)
        try write(invalid)
        #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine) == nil)
        try write([])
        #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine) == nil)
    }
}
