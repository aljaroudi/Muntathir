import Foundation
@testable import Muntathir
import Testing

struct DailyVerseScheduleTests {
    @Test func completeScheduleMapsEveryHijriDateByArrayPosition() throws {
        let url = try #require(Bundle.main.url(forResource: "quran-daily-ids", withExtension: "json"))
        let ids = try JSONDecoder().decode([Int].self, from: Data(contentsOf: url))
        let records = QuranDatabase().verses(ids: Set(ids))
        let library = ContentLibrary()
        #expect(ids.count == 360)
        for month in 1 ... 12 {
            for day in 1 ... 30 {
                let resolved = ResolvedDay(month: .init(year: 1448, month: month), day: day, provenance: .calculated, sourceID: nil)
                #expect(library.verse(on: resolved)?.id == records[ids[(month - 1) * 30 + day - 1]]?.id)
            }
        }
        #expect(ids[39] == 1548)
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

    @Test func bundledRotationFollowsCorrectedIslamicDate() throws {
        let baseline = try CalendarEngine(timeZone: .gmt)
        let month = HijriMonth(year: 1448, month: 5)
        let date = baseline.addingDays(1, to: baseline.start(of: month))
        let correction = MonthCorrection(month: month, start: CivilDate(date, in: .gmt), provenance: .manual, sourceID: nil)
        let corrected = try CalendarEngine(timeZone: .gmt, manual: [correction])
        let widget = WidgetCalendarSettings(timeZoneID: "GMT", manual: [correction]).engine
        let library = ContentLibrary()
        let verse = try #require(library.verse(on: date, engine: corrected))
        #expect(verse.id != library.verse(on: date, engine: baseline)?.id)
        #expect(verse.id == library.verse(on: baseline.start(of: month), engine: baseline)?.id)
        #expect(verse.id == library.verse(on: date, engine: widget)?.id)
        #expect(verse.id == library.verse(on: date.addingTimeInterval(86399), engine: corrected)?.id)
    }

    @Test(arguments: ["Asia/Riyadh", "America/New_York"])
    func sunsetSelectsNextHijriDayAndKeepsItThroughMidnight(zoneID: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        let engine = try CalendarEngine(timeZone: zone)
        let location = SavedLocation(latitude: zoneID == "Asia/Riyadh" ? 24.7136 : 40.7128,
                                     longitude: zoneID == "Asia/Riyadh" ? 46.6753 : -74.006,
                                     name: "Test", countryCode: "", timeZoneID: zoneID)
        let prayers = WidgetPrayerSettings(location: location, method: .jafari, hiddenPrayers: [.sunset])
        let start = try #require(CivilDate(year: 2026, month: 3, day: 7).date(in: zone))
        let library = ContentLibrary()
        for offset in 0 ..< 3 {
            let date = engine.addingDays(offset, to: start)
            let sunset = try #require(prayers.sunset(on: date))
            let maghrib = try #require(PrayerCalculator.times(on: date, location: location, method: .jafari).first { $0.name == .maghrib }?.date)
            #expect(sunset < maghrib)
            let otherMethod = WidgetPrayerSettings(location: location, method: .ummAlQura, hiddenPrayers: [])
            #expect(sunset == otherMethod.sunset(on: date))
            let tomorrow = engine.addingDays(1, to: date)
            let current = engine.resolve(date)
            let next = engine.resolve(tomorrow)
            #expect(ContentLibrary.verseDay(on: sunset.addingTimeInterval(-1), engine: engine, prayerSettings: prayers).day == current.day)
            for instant in [sunset, sunset.addingTimeInterval(1), tomorrow, tomorrow.addingTimeInterval(1)] {
                let resolved = ContentLibrary.verseDay(on: instant, engine: engine, prayerSettings: prayers)
                #expect(resolved.month == next.month && resolved.day == next.day)
                #expect(library.verse(on: instant, engine: engine, prayerSettings: prayers)?.id == library.verse(on: next)?.id)
            }
        }
        let dates = prayers.dailyVerseTimelineDates(from: start, engine: engine)
        #expect(dates.count == 8)
        for boundary in dates.dropFirst() {
            #expect(boundary == prayers.sunset(on: boundary))
            #expect(library.verse(on: boundary, engine: engine, prayerSettings: prayers)?.id
                != library.verse(on: boundary.addingTimeInterval(-1), engine: engine, prayerSettings: prayers)?.id)
        }
    }

    @Test func sunsetFollowsCorrectedMonthLengthsAndYearRollover() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let baseline = try CalendarEngine(timeZone: zone)
        let month = HijriMonth(year: 1448, month: 1)
        let correction = MonthCorrection(month: month, start: CivilDate(baseline.addingDays(1, to: baseline.start(of: month)), in: zone),
                                         provenance: .manual, sourceID: nil)
        let engine = try CalendarEngine(timeZone: zone, manual: [correction])
        let widget = WidgetCalendarSettings(timeZoneID: zone.identifier, manual: [correction]).engine
        let prayers = WidgetPrayerSettings(location: SavedLocation(latitude: 24.7136, longitude: 46.6753, name: "Riyadh",
                                                                   countryCode: "SA", timeZoneID: zone.identifier),
                                           method: .jafari, hiddenPrayers: [])
        var lengths = Set<Int>()
        for offset in 0 ..< 13 {
            let nextMonth = month.advanced(offset)
            let start = engine.start(of: nextMonth)
            let preceding = engine.addingDays(-1, to: start)
            let previous = engine.resolve(preceding)
            lengths.insert(previous.day)
            let boundary = try #require(prayers.sunset(on: preceding))
            for calendar in [engine, widget] {
                let before = ContentLibrary.verseDay(on: boundary.addingTimeInterval(-1), engine: calendar, prayerSettings: prayers)
                let after = ContentLibrary.verseDay(on: boundary, engine: calendar, prayerSettings: prayers)
                #expect(before.month == previous.month && before.day == previous.day)
                #expect(after.month == nextMonth && after.day == 1)
            }
        }
        #expect(lengths == [29, 30])
    }

    @Test func missingOrUncalculableSunsetFallsBackToMidnight() throws {
        let engine = try CalendarEngine(timeZone: .gmt)
        let date = try #require(CivilDate(year: 2026, month: 3, day: 7).date(in: .gmt)).addingTimeInterval(23 * 3600)
        let invalid = SavedLocation(latitude: .nan, longitude: 0, name: "Invalid", countryCode: "", timeZoneID: "GMT")
        for location in [nil, invalid] {
            let prayers = WidgetPrayerSettings(location: location, method: .jafari, hiddenPrayers: [])
            #expect(prayers.sunset(on: date) == nil)
            #expect(ContentLibrary.verseDay(on: date, engine: engine, prayerSettings: prayers).day == engine.resolve(date).day)
            let dates = prayers.dailyVerseTimelineDates(from: date, engine: engine)
            #expect(dates.count == 8)
            #expect(dates.dropFirst().allSatisfy { engine.gregorian.component(.hour, from: $0) == 0 })
        }
    }

    @Test func databaseContainsTheCompleteArabicQuranAndIsReadOnly() throws {
        let url = try #require(Bundle.main.url(forResource: "quran", withExtension: "db"))
        let before = try Data(contentsOf: url)
        let verses = QuranDatabase(url: url).verses(ids: Set(1 ... 6236))
        #expect(verses.count == 6236)
        #expect(verses[1]?.id == "1:1")
        #expect(verses[6236]?.id == "114:6")
        #expect(verses.values.allSatisfy { !$0.text.isEmpty && $0.translations.isEmpty })
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
        #expect(appVerses.count == 360)
        #expect(appVerses.map(\.id) == widgetVerses.map(\.id))
        #expect(appVerses.map(\.text) == widgetVerses.map(\.text))
        let appDB = try #require(Bundle.main.url(forResource: "quran", withExtension: "db"))
        let widgetDB = try #require(widget.url(forResource: "quran", withExtension: "db"))
        #expect(try Data(contentsOf: appDB) == Data(contentsOf: widgetDB))
        for translation in QuranTranslation.catalog {
            #expect(Bundle.main.url(forResource: translation.id, withExtension: "db") == nil)
            #expect(widget.url(forResource: translation.id, withExtension: "db") == nil)
        }
    }

    @Test func completeDatasetActivatesAndInvalidReferenceNeverFallsBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.daily-verses"], format: .xml, options: 0)
        try info.write(to: folder.appendingPathComponent("Info.plist"))
        for name in ["quran"] {
            let source = try #require(Bundle.main.url(forResource: name, withExtension: "db"))
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("\(name).db"))
        }
        let resource = folder.appendingPathComponent("quran-daily-ids.json")
        func write(_ ids: [Int]) throws {
            try JSONEncoder().encode(ids).write(to: resource)
        }
        let ids = Array(1 ... 360)
        try write(ids)
        let bundle = try #require(Bundle(url: folder))
        let engine = try CalendarEngine(timeZone: .gmt)
        let date = engine.start(of: .init(year: 1448, month: 1))
        #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine)?.id == "1:1")
        for invalid in [Array(ids.dropLast()), ids + [361], [99999] + Array(ids.dropFirst()),
                        [0] + Array(ids.dropFirst()), [-1] + Array(ids.dropFirst()), []]
        {
            try write(invalid)
            #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine) == nil)
        }
        try Data("invalid JSON".utf8).write(to: resource)
        #expect(ContentLibrary(bundle: bundle).verse(on: date, engine: engine) == nil)
    }
}
