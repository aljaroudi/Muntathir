import Foundation
@testable import Muntathir
import Testing

struct CalendarTests {
    let zone = TimeZone(identifier: "Asia/Riyadh")!
    @Test func baselineAndManualPrecedence() throws {
        let month = HijriMonth(year: 1448, month: 1)
        let base = try CalendarEngine(timeZone: zone)
        let moved = base.addingDays(1, to: base.start(of: month))
        let confirmed = MonthCorrection(month: month, start: CivilDate(base.start(of: month), in: zone), provenance: .confirmed, sourceID: "example")
        let manual = MonthCorrection(month: month, start: CivilDate(moved, in: zone), provenance: .manual, sourceID: nil)
        let engine = try CalendarEngine(timeZone: zone, manual: [manual], confirmed: [confirmed])
        #expect(engine.resolve(moved).day == 1)
        #expect(engine.resolve(moved).provenance == .manual)
        #expect(base.resolve(moved).day == 2)
        let ashura = engine.addingDays(9, to: moved)
        #expect(engine.resolve(ashura).day == 10)
        #expect(ContentLibrary().events(on: engine.resolve(ashura)).contains { $0.id == "husayn-death" })
    }

    @Test(arguments: [-3, -1, 1, 3]) func allNeighboringMonthsRemainValid(offset: Int) throws {
        let base = try CalendarEngine(timeZone: zone)
        let month = HijriMonth(year: 1448, month: 1)
        let row = MonthCorrection(month: month, start: CivilDate(base.addingDays(offset, to: base.start(of: month)), in: zone), provenance: .manual, sourceID: nil)
        let engine = try CalendarEngine(timeZone: zone, manual: [row])
        for index in -12 ... 12 {
            let candidate = month.advanced(index)
            #expect((29 ... 30).contains(engine.days(in: candidate).count))
            #expect(engine.resolve(engine.start(of: candidate)).month == candidate)
            #expect(engine.resolve(engine.start(of: candidate)).day == 1)
        }
    }

    @Test func rejectConflictingAnchorsAndInvalidDates() throws {
        let base = try CalendarEngine(timeZone: zone), month = HijriMonth(year: 1448, month: 1)
        let first = MonthCorrection(month: month, start: CivilDate(base.start(of: month), in: zone), provenance: .manual, sourceID: nil)
        let second = MonthCorrection(month: month.advanced(1), start: CivilDate(base.addingDays(28, to: base.start(of: month)), in: zone), provenance: .manual, sourceID: nil)
        #expect(throws: CalendarError.self) { try CalendarEngine(timeZone: zone, manual: [first, second]) }
        #expect(CivilDate(year: 2026, month: 2, day: 30).date(in: zone) == nil)
    }

    @Test func futureAnchorConverges() throws {
        let base = try CalendarEngine(timeZone: zone), month = HijriMonth(year: 1448, month: 1)
        let rows = [month, month.advanced(4)].map { MonthCorrection(month: $0, start: CivilDate(base.addingDays(1, to: base.start(of: $0)), in: zone), provenance: .manual, sourceID: nil) }
        let engine = try CalendarEngine(timeZone: zone, manual: rows)
        #expect((0 ..< 5).allSatisfy { (29 ... 30).contains(engine.days(in: month.advanced($0)).count) })
        #expect(engine.resolve(engine.start(of: month.advanced(2))).provenance == .calculated)
    }
}

struct ContentTests {
    @Test(arguments: [("en_US", "Eid al-Fitr"), ("ar_SA", "عيد الفطر"),
                      ("fr_CA", "Aïd al-Fitr"), ("zh_Hans", "开斋节"), ("zh_Hant", "開齋節")])
    func eventTitlesUseStringCatalog(identifier: String, expected: String) {
        let event = IslamicEvent(id: "fitr", month: 10, day: 1)
        #expect(event.title(locale: Locale(identifier: identifier)) == expected)
    }

    @Test func eventDatesSurviveCoding() throws {
        let original = IslamicEvent(id: "fitr", month: 10, day: 1)
        let decoded = try JSONDecoder().decode(IslamicEvent.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func eventYearMetadataSurvivesCoding() throws {
        let original = IslamicEvent(id: "husayn-death", month: 1, day: 10, year: 61)
        let decoded = try JSONDecoder().decode(IslamicEvent.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.yearText(locale: Locale(identifier: "en")) == "61 AH")
        let beforeHijra = IslamicEvent(id: "prophet-birth", month: 3, day: 17, year: -53)
        #expect(beforeHijra.yearText(locale: Locale(identifier: "en")) == "-53 AH")
    }

    @Test func missingContentHasNoDailyVerse() throws {
        let emptyBundle = try #require(Bundle(identifier: "com.apple.Foundation"))
        #expect(try ContentLibrary(bundle: emptyBundle).verse(on: Date(), engine: CalendarEngine(timeZone: .gmt)) == nil)
    }

    @Test func bundledContentIsCompleteAndStable() throws {
        let library = ContentLibrary()
        #expect(library.verses.count == 360)
        #expect(library.events.count >= 30)
        for event in library.events {
            for language in ["en", "ar"] {
                let title = event.title(locale: Locale(identifier: language))
                #expect(title != "event.\(event.id)")
                #expect(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            }
        }
        #expect(Set(library.events.map(\.id)).count == library.events.count)
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let day = try #require(CivilDate(year: 2026, month: 10, day: 17).date(in: zone))
        #expect(try library.verse(on: day, engine: CalendarEngine(timeZone: zone))?.id == library.verse(on: day.addingTimeInterval(300), engine: CalendarEngine(timeZone: zone))?.id)
        #expect(try library.verse(on: day, engine: CalendarEngine(timeZone: zone))?.id != library.verse(on: day.addingTimeInterval(86400), engine: CalendarEngine(timeZone: zone))?.id)
    }
}

struct PrayerTests {
    struct Fixture: Decodable {
        struct Params: Decodable { let latitude: Double; let longitude: Double; let timezone: String; let madhab: String }
        let params: Params
        let variance: Int?
        let times: [[String: String]]
    }

    @Test func matchesTehranReferenceFixture() throws {
        let name = "Tehran-Tehran"
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let location = SavedLocation(latitude: fixture.params.latitude, longitude: fixture.params.longitude, name: name, countryCode: "", timeZoneID: fixture.params.timezone)
        let method: PrayerMethod = .tehran
        let dateParser = DateFormatter(); dateParser.locale = Locale(identifier: "en_US_POSIX"); dateParser.timeZone = location.timeZone; dateParser.dateFormat = "yyyy-MM-dd"
        let timeParser = DateFormatter(); timeParser.locale = Locale(identifier: "en_US_POSIX"); timeParser.timeZone = location.timeZone; timeParser.dateFormat = "yyyy-MM-dd h:mm a"
        for row in fixture.times {
            let day = try #require(row["date"]), date = try #require(dateParser.date(from: day))
            let times = PrayerCalculator.times(on: date, location: location, method: method)
            #expect(times.count == 9)
            for prayer in times where prayer.name != .sunset && prayer.name != .midnight && prayer.name != .imsak {
                // The London fixture uses Hanafi Asr; this app always uses standard Asr.
                if prayer.name == .asr, fixture.params.madhab == "Hanafi" {
                    continue
                }
                let expectedText = try #require(row[prayer.name.rawValue])
                let expected = try #require(timeParser.date(from: day + " " + expectedText))
                #expect(abs(prayer.date.timeIntervalSince(expected)) <= Double(max(1, fixture.variance ?? 1) * 60))
            }
        }
    }

    @Test func highLatitudeFailureIsHonest() throws {
        let location = SavedLocation(latitude: 89, longitude: 0, name: "Polar", countryCode: "", timeZoneID: "GMT")
        let date = try #require(CivilDate(year: 2026, month: 6, day: 21).date(in: .gmt))
        #expect(PrayerCalculator.times(on: date, location: location, method: .tehran).isEmpty)
    }

    @Test func schedulesFuturePrayersOnly() throws {
        let location = SavedLocation(latitude: 24.7, longitude: 46.7, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        var preferences = Preferences(); preferences.enabledPrayers = [.fajr, .maghrib]
        let now = try #require(CivilDate(year: 2026, month: 10, day: 17).date(in: location.timeZone))
        let plan = NotificationPlan.make(now: now, preferences: preferences, location: location)
        #expect(!plan.isEmpty && plan.count <= 20)
        #expect(plan.allSatisfy { $0.date > now && preferences.enabledPrayers.contains($0.name) })
        #expect(Set(plan.map(\.id)).count == plan.count)
        preferences.enabledPrayers = []
        #expect(NotificationPlan.make(now: now, preferences: preferences, location: location).isEmpty)
    }
}

private final class BundleMarker: NSObject {}

struct FeedTests {
    @Test func sharedFixtureDecodes() throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "corrections-v1", withExtension: "json"))
        #expect(try CorrectionsFeed.decode(Data(contentsOf: url)).announcements.count == 1)
    }

    @Test func coverageAndSelectedSource() throws {
        let location = SavedLocation(latitude: 24, longitude: 46, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let polygon = Coverage(countries: [], polygons: [[.init(latitude: 20, longitude: 40), .init(latitude: 30, longitude: 40), .init(latitude: 30, longitude: 50), .init(latitude: 20, longitude: 50)]])
        #expect(polygon.contains(location))
        #expect(!Coverage(countries: ["IQ"], polygons: []).contains(location))
        let engine = try CalendarEngine(timeZone: location.timeZone), month = HijriMonth(year: 1448, month: 1)
        let row = Announcement(id: "example", revision: 1, method: .nakedEye, sourceID: CalendarSource.middleEast, coverage: polygon, month: month, start: CivilDate(engine.start(of: month), in: location.timeZone))
        let feed = try CorrectionsFeed.decode(JSONEncoder().encode(CorrectionsFeed(schemaVersion: 1, announcements: [row])))
        #expect(try feed.matching(location: location, sourceID: nil).isEmpty)
        #expect(try feed.matching(location: location, sourceID: "other").isEmpty)
        #expect(try feed.matching(location: location, sourceID: CalendarSource.middleEast).count == 1)
        #expect(throws: CalendarError.self) { try CorrectionsFeed.decode(JSONEncoder().encode(CorrectionsFeed(schemaVersion: 2, announcements: []))) }
        #expect(throws: CalendarError.self) { try CorrectionsFeed.decode(JSONEncoder().encode(CorrectionsFeed(schemaVersion: 1, announcements: [row, row]))) }
    }

    @Test func dateLinePolygon() {
        let coverage = Coverage(countries: [], polygons: [[.init(latitude: -10, longitude: 170), .init(latitude: 10, longitude: 170), .init(latitude: 10, longitude: -170), .init(latitude: -10, longitude: -170)]])
        #expect(coverage.contains(.init(latitude: 0, longitude: 179, name: "Date line", countryCode: "", timeZoneID: "GMT")))
        #expect(!coverage.contains(.init(latitude: 0, longitude: 0, name: "Greenwich", countryCode: "", timeZoneID: "GMT")))
    }
}

@MainActor struct PreferenceTests {
    @Test func persistsSavedChoicesAndDeviceLocalGPS() throws {
        let suite = "Muntathir.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        let saved = SavedLocation(latitude: 24, longitude: 46, name: "Saved", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        model.select(saved)
        model.applyLive(.init(latitude: 25, longitude: 47, name: "Live", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        model.update { $0.prayerMethod = .ummAlQura; $0.hiddenPrayers = [.asr, .isha] }
        let restored = AppModel(defaults: defaults, cloud: nil)
        #expect(restored.location == model.liveLocation)
        #expect(restored.liveLocation != nil)
        #expect(restored.preferences.savedLocation == saved)
        #expect(restored.preferences.prayerMethod == .ummAlQura)
        #expect(restored.preferences.enabledPrayers == [.fajr, .dhuhr, .maghrib])
        #expect(!restored.preferences.isVisible(.asr))
        #expect(!restored.preferences.isVisible(.isha))
        restored.select(saved)
        #expect(AppModel(defaults: defaults, cloud: nil).liveLocation == nil)
    }
}

struct PrayerBoundaryTests {
    @Test(arguments: [CivilDate(year: 2026, month: 1, day: 1), CivilDate(year: 2026, month: 6, day: 1)])
    func tehranMaghribIsAfterSunset(day: CivilDate) throws {
        let location = SavedLocation(latitude: 24.7, longitude: 46.7, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let date = try #require(day.date(in: location.timeZone))
        let shia = try #require(PrayerCalculator.times(on: date, location: location, method: .tehran).first { $0.name == .maghrib })
        let sunset = try #require(PrayerCalculator.times(on: date, location: location, method: .ummAlQura).first { $0.name == .maghrib })
        #expect(shia.date > sunset.date)
    }

    @Test func correctionsDoNotChangePrayerMath() throws {
        let location = SavedLocation(latitude: 24.7, longitude: 46.7, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let date = try #require(CivilDate(year: 2026, month: 3, day: 1).date(in: location.timeZone))
        let times = PrayerCalculator.times(on: date, location: location, method: .ummAlQura)
        let maghrib = try #require(times.first { $0.name == .maghrib })
        let isha = try #require(times.first { $0.name == .isha })
        #expect(isha.date.timeIntervalSince(maghrib.date) == 120 * 60)
    }
}

struct MeccaPrayerTests {
    @Test(arguments: [PrayerMethod.jafari, .tehran]) func todayInMeccaHasEveryPrayer(method: PrayerMethod) throws {
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let date = try #require(CivilDate(year: 2026, month: 10, day: 17).date(in: location.timeZone))
        let prayers = PrayerCalculator.times(on: date, location: location, method: method)
        #expect(prayers.map(\.name) == PrayerName.allCases)
        let calendar = try CalendarEngine(timeZone: location.timeZone).gregorian
        let maghrib = try #require(prayers.first { $0.name == .maghrib })
        #expect(calendar.component(.hour, from: maghrib.date) == 18)
        #expect(calendar.component(.minute, from: maghrib.date) == (method == .jafari ? 9 : 11))
    }

    @Test func gpsWithoutPlaceNameStillCalculates() throws {
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "", countryCode: "", timeZoneID: "Asia/Riyadh")
        let date = try #require(CivilDate(year: 2026, month: 10, day: 17).date(in: location.timeZone))
        #expect(PrayerCalculator.times(on: date, location: location, method: .tehran).count == 9)
    }
}

struct PreferenceMigrationTests {
    @Test func oldSettingsKeepLocationAndDefaultToAllVisible() throws {
        let json = #"{"savedLocation":{"latitude":21.4225,"longitude":39.8262,"name":"Mecca","countryCode":"SA","timeZoneID":"Asia/Riyadh"},"prayerMethod":"tehran"}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.savedLocation?.name == "Mecca")
        #expect(preferences.hiddenPrayers.isEmpty)
    }
}

@MainActor struct BackgroundRefreshTests {
    @Test func appLaunchRegistersRefreshHandler() {
        #expect(BackgroundRefresh.isRegistered)
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(identifiers?.contains(BackgroundRefresh.identifier) == true)
    }
}

extension CalendarTests {
    @Test(arguments: [-2, -1, 0, 1, 2])
    func sourceRelativeOffsetsPreserveBoundaries(days: Int) throws {
        let month = HijriMonth(year: 1448, month: 1)
        let baseline = try CalendarEngine(timeZone: zone)
        let confirmation = MonthCorrection(month: month,
                                           start: CivilDate(baseline.addingDays(1, to: baseline.start(of: month)), in: zone),
                                           provenance: .confirmed, sourceID: CalendarSource.middleEast)
        let source = try CalendarEngine(timeZone: zone, confirmed: [confirmation])
        let offset = MonthOffset(month: month, days: days)
        let engine = try CalendarEngine(timeZone: zone, offsets: [offset], confirmed: [confirmation])
        #expect(engine.start(of: month) == source.addingDays(-days, to: source.start(of: month)))
        #expect(engine.resolve(engine.start(of: month)).day == 1)
        #expect(engine.resolve(engine.start(of: month)).provenance == (days == 0 ? .confirmed : .manual))
        for index in -12 ... 12 {
            let candidate = month.advanced(index)
            #expect((29 ... 30).contains(engine.days(in: candidate).count))
            #expect(engine.resolve(engine.start(of: candidate)).month == candidate)
        }
        let manual = engine.corrections.values.filter { $0.provenance == .manual }
        let widget = WidgetCalendarSettings(timeZoneID: zone.identifier, manual: manual, confirmed: [confirmation])
        let watch = WatchSettings(prayers: .init(location: nil, method: .jafari, hiddenPrayers: []), calendar: widget)
        #expect(widget.engine.start(of: month) == engine.start(of: month))
        #expect(try WatchSettings.decode(watch.encoded()).calendar.engine.start(of: month) == engine.start(of: month))
    }

    @MainActor @Test func monthOffsetPersistenceMigrationAndConflictRejection() throws {
        let suite = "CalendarOffset.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"prayerMethod":"tehran","showFeelsLikeTemperature":true,"selectedSourceID":"legacy","overrides":[{"month":{"year":1448,"month":1},"start":{"year":2026,"month":6,"day":16},"provenance":"manual"}]}"#.utf8), forKey: "preferences.v1")
        let model = AppModel(defaults: defaults, cloud: nil)
        #expect(model.preferences.monthOffsets.isEmpty)
        #expect(model.preferences.selectedSourceID == nil)
        #expect(model.preferences.prayerMethod == .tehran)
        #expect(model.preferences.showFeelsLikeTemperature)
        let month = HijriMonth(year: 1448, month: 12)
        try model.correct(month: month, offset: -2)
        let saved = model.preferences
        #expect(throws: CalendarError.self) { try model.correct(month: month.advanced(1), offset: 2) }
        #expect(model.preferences == saved)
        #expect(throws: CalendarError.self) { try model.correct(month: month, offset: 3) }
        let restored = AppModel(defaults: defaults, cloud: nil)
        #expect(restored.preferences.monthOffsets == saved.monthOffsets)
        try restored.correct(month: month, offset: 0)
        #expect(restored.preferences.monthOffsets.isEmpty)
        #expect(restored.engine.start(of: month) == restored.engine.baselineStart(month))
        #expect(try String(decoding: JSONEncoder().encode(restored.preferences), as: UTF8.self).contains("overrides") == false)
    }

    @Test func knownSourcesApplyWorldwideAndRequireMatchingMethod() throws {
        let location = SavedLocation(latitude: 51.5, longitude: -0.1, name: "London", countryCode: "GB", timeZoneID: "Europe/London")
        let coverage = Coverage(countries: ["SA"], polygons: [])
        let month = HijriMonth(year: 1448, month: 1)
        let base = try CalendarEngine(timeZone: location.timeZone)
        for source in [CalendarSource.middleEast] + CalendarSource.countries.map({ "government-" + $0 }) {
            let method = try #require(CalendarSource.sightingMethod(for: source))
            let row = Announcement(id: source, revision: 1, method: method, sourceID: source, coverage: coverage,
                                   month: month, start: CivilDate(base.start(of: month), in: location.timeZone))
            let wrong = Announcement(id: source + "-wrong", revision: 1, method: .aidedSight, sourceID: source,
                                     coverage: coverage, month: month, start: row.start)
            let feed = CorrectionsFeed(schemaVersion: 1, announcements: [row, wrong])
            #expect(try feed.matching(location: location, sourceID: source) == [row])
            #expect(try feed.matching(location: location, sourceID: nil).isEmpty)
            #expect(try feed.matching(location: location, sourceID: "unknown").isEmpty)
        }
    }
}

extension CalendarTests {
    @Test(arguments: ["en", "ar", "fr", "de", "id", "it", "ja", "ms", "fa", "ru", "es", "tr", "ur", "zh-Hans", "zh-Hant"])
    func supportedLanguagesAreBundled(language: String) throws {
        let app = Bundle.main
        let relativeBundles = ["", "PlugIns/MuntathirWidgets.appex", "Watch/MuntathirWatch.app",
                               "Watch/MuntathirWatch.app/PlugIns/MuntathirWatchWidgets.appex"]
        for path in relativeBundles {
            let url = app.bundleURL.appendingPathComponent(path)
            let bundle = try #require(Bundle(url: url))
            #expect(bundle.localizations.contains(language))
            let translation = try #require(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let contents = try Data(contentsOf: translation)
            let strings = try #require(try PropertyListSerialization.propertyList(from: contents, format: nil) as? [String: String])
            #expect(strings["Calendar"]?.isEmpty == false)
            #expect(strings["System calendar"]?.isEmpty == false)
            #expect(strings["Day adjustment"]?.isEmpty == false)
            if language != "en" {
                #expect(strings["System calendar"] != "System calendar")
            }
        }
    }
}
