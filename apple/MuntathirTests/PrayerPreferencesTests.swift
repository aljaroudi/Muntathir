import Foundation
@testable import Muntathir
import Testing

struct PrayerPreferencesTests {
    private let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")

    @Test func freshCalendarDefaultPreservesSavedSystemChoice() throws {
        #expect(Preferences().selectedSourceID == CalendarSource.middleEast)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(saved.selectedSourceID == nil)
        var government = Preferences()
        government.selectedSourceID = "government-SA"
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(government)).selectedSourceID == "government-SA")
    }

    @Test func oldSettingsKeepChoicesAndDefaultNewFields() throws {
        let data = Data(#"{"prayerMethod":"tehran","asrRule":"hanafi","enabledPrayers":[],"hiddenPrayers":["asr"]}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(preferences.prayerMethod == .tehran)
        #expect(preferences.enabledPrayers.isEmpty)
        #expect(preferences.imsakMinutes == 10)
        #expect(preferences.hiddenPrayers == [.asr])
        #expect(Preferences().enabledPrayers == [.fajr, .dhuhr, .maghrib])
        let fresh = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(fresh.prayerMethod == .tehran)
        #expect(fresh.enabledPrayers == [.fajr, .dhuhr, .maghrib])
        let encoded = try JSONEncoder().encode(preferences)
        #expect(String(decoding: encoded, as: UTF8.self).contains("asrRule") == false)
        let oldWidget = Data(#"{"method":"tehran","asrRule":"hanafi","hiddenPrayers":[]}"#.utf8)
        #expect(try JSONDecoder().decode(WidgetPrayerSettings.self, from: oldWidget).imsakMinutes == 10)
    }

    @Test(arguments: [0, 10, 25, 120])
    func imsakOffsetReachesScheduleWidgetsWatchAndNotifications(minutes: Int) throws {
        let date = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        var preferences = Preferences()
        preferences.prayerMethod = .tehran
        preferences.imsakMinutes = minutes
        preferences.enabledPrayers = [.imsak]
        let settings = WidgetPrayerSettings(location: location, method: .tehran, hiddenPrayers: [], imsakMinutes: minutes)
        let times = settings.prayers(on: date)
        let imsak = try #require(times.first { $0.name == .imsak })
        let fajr = try #require(times.first { $0.name == .fajr })
        #expect(fajr.date.timeIntervalSince(imsak.date) == Double(minutes * 60))
        let plan = NotificationPlan.make(now: date, preferences: preferences, location: location)
        #expect(plan.first?.name == .imsak)
        #expect(plan.first?.date == imsak.date)
        let watch = WatchSettings(prayers: settings, calendar: .init())
        #expect(try WatchSettings.decode(watch.encoded()).prayers.imsakMinutes == minutes)
        #expect(settings.nextPrayer(after: date)?.name == .fajr)
    }

    @Test func imsakPreferenceBoundsAreValidatedOnDecode() throws {
        #expect(try JSONDecoder().decode(Preferences.self, from: Data(#"{"imsakMinutes":-5}"#.utf8)).imsakMinutes == 0)
        #expect(try JSONDecoder().decode(Preferences.self, from: Data(#"{"imsakMinutes":999}"#.utf8)).imsakMinutes == 120)
    }
}

extension PrayerPreferencesTests {
    @Test(arguments: [-2, -1, 0, 1, 2])
    func calendarOffsetsNeverChangePrayers(days: Int) throws {
        let date = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        var original = Preferences()
        original.prayerMethod = .ummAlQura
        let before = NotificationPlan.make(now: date, preferences: original, location: location)
        var adjusted = original
        adjusted.monthOffsets = [.init(month: .init(year: 1448, month: 9), days: days)]
        let after = NotificationPlan.make(now: date, preferences: adjusted, location: location)
        #expect(before.map(\.date) == after.map(\.date))
        #expect(before.map(\.name) == after.map(\.name))
    }
}

extension PrayerPreferencesTests {
    @Test func eventRemindersUseCorrectedTomorrowAtSunsetAndCombineEvents() throws {
        let now = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        let base = try CalendarEngine(timeZone: location.timeZone)
        let month = base.resolve(now).month
        let engine = try CalendarEngine(timeZone: location.timeZone, offsets: [.init(month: month, days: 1)])
        let tomorrow = engine.resolve(engine.addingDays(1, to: now))
        let events = ["b", "a"].map { IslamicEvent(id: $0, month: tomorrow.month.month, day: tomorrow.day, title: ["en": $0]) }
        var prefs = Preferences()
        #expect(NotificationPlan.events(now: now, preferences: prefs, location: location, engine: engine, events: events).isEmpty)
        prefs.calendarEventNotifications = true
        let plan = NotificationPlan.events(now: now, preferences: prefs, location: location, engine: engine, events: events)
        let alert = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(alert.events.map(\.id) == ["a", "b"])
        let sunset = try #require(WidgetPrayerSettings(location: location, method: prefs.prayerMethod, hiddenPrayers: []).sunset(on: now))
        #expect(alert.date == sunset)
        #expect(NotificationPlan.events(now: sunset, preferences: prefs, location: location, engine: engine, events: events).isEmpty)
        #expect(NotificationPlan.events(now: now, preferences: prefs, location: location, engine: base, events: events).first?.date != sunset)
    }

    @Test func combinedNotificationBudgetKeepsNearestFifty() {
        let requests = (0 ..< 80).reversed().map { ScheduledAlert(id: "\($0)", date: Date(timeIntervalSince1970: Double($0)), prayer: $0.isMultiple(of: 2) ? .fajr : nil, events: []) }
        let selected = NotificationPlan.nearest(requests)
        #expect(selected.count == 50)
        #expect(selected.first?.id == "0")
        #expect(selected.last?.id == "49")
    }
}

extension PrayerPreferencesTests {
    @Test func polarDatesWithoutSunsetDoNotInventEventTimes() throws {
        let polar = SavedLocation(latitude: 78.2232, longitude: 15.6469, name: "Longyearbyen", countryCode: "NO", timeZoneID: "Arctic/Longyearbyen")
        let now = try #require(CivilDate(year: 2026, month: 6, day: 21).date(in: polar.timeZone))
        let engine = try CalendarEngine(timeZone: polar.timeZone)
        let tomorrow = engine.resolve(engine.addingDays(1, to: now))
        var preferences = Preferences()
        preferences.calendarEventNotifications = true
        let events = [IslamicEvent(id: "test", month: tomorrow.month.month, day: tomorrow.day, title: ["en": "Test"])]
        #expect(NotificationPlan.events(now: now, preferences: preferences, location: polar, engine: engine, events: events).isEmpty)
    }

    @Test(arguments: ["America/New_York", "Asia/Riyadh"])
    func eventRemindersUseLocationTimezone(zoneID: String) throws {
        let place = SavedLocation(latitude: 40.7128, longitude: -74.006, name: "Test", countryCode: "US", timeZoneID: zoneID)
        let now = try #require(CivilDate(year: 2026, month: 11, day: 1).date(in: place.timeZone))
        let engine = try CalendarEngine(timeZone: place.timeZone)
        let day = engine.resolve(engine.addingDays(1, to: now))
        var preferences = Preferences()
        preferences.calendarEventNotifications = true
        let events = [IslamicEvent(id: "test", month: day.month.month, day: day.day, title: ["en": "Test"])]
        let alert = try #require(NotificationPlan.events(now: now, preferences: preferences, location: place, engine: engine, events: events).first)
        #expect(alert.date == WidgetPrayerSettings(location: place, method: preferences.prayerMethod, hiddenPrayers: []).sunset(on: now))
    }
}
