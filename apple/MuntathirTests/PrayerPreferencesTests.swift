import Foundation
@testable import Muntathir
import Testing

struct PrayerPreferencesTests {
    private let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")

    @Test func oldSettingsKeepChoicesAndDefaultNewFields() throws {
        let data = Data(#"{"prayerMethod":"tehran","asrRule":"hanafi","enabledPrayers":[],"hiddenPrayers":["asr"]}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(preferences.enabledPrayers.isEmpty)
        #expect(preferences.imsakMinutes == 10)
        #expect(preferences.hiddenPrayers == [.asr])
        #expect(Preferences().enabledPrayers == [.fajr, .dhuhr, .maghrib])
        #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).enabledPrayers == [.fajr, .dhuhr, .maghrib])
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
