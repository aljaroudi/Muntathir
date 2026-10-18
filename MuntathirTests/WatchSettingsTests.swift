import Foundation
@testable import Muntathir
import Testing

struct WatchSettingsTests {
    private let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")

    @Test func settingsPersistAndInvalidTransfersKeepLastGoodSnapshot() throws {
        let suite = "Watch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WatchSettings(prayers: .init(location: location, method: .jafari, asrRule: .standard, hiddenPrayers: [.asr, .isha]), calendar: .init(timeZoneID: location.timeZoneID))
        let engine = try CalendarEngine(timeZone: location.timeZone)
        let month = HijriMonth(year: 1448, month: 5)
        let start = engine.addingDays(1, to: engine.start(of: month))
        settings.calendar.manual = [.init(month: month, start: CivilDate(start, in: location.timeZone), provenance: .manual, sourceID: nil)]
        try WatchSettings.receive(settings.encoded(), in: defaults)
        let restored = try #require(WatchSettings.read(from: defaults))
        #expect(restored == settings)
        #expect(restored.calendar.engine.resolve(start).day == 1)
        #expect(throws: (any Error).self) { try WatchSettings.receive(Data("bad".utf8), in: defaults) }
        var unknown = settings
        unknown.version = 99
        #expect(throws: (any Error).self) { try WatchSettings.receive(unknown.encoded(), in: defaults) }
        #expect(WatchSettings.read(from: defaults) == settings)
        settings.prayers.location = nil
        try WatchSettings.receive(settings.encoded(), in: defaults)
        #expect(WatchSettings.read(from: defaults)?.prayers.location == nil)
    }

    @Test func upcomingPrayersSkipHiddenTimesOnPhoneAndWatch() throws {
        let settings = WidgetPrayerSettings(location: location, method: .tehran, asrRule: .standard, hiddenPrayers: [.asr, .isha])
        let date = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        let times = settings.prayers(on: date)
        let dhuhr = try #require(times.first { $0.name == .dhuhr })
        let maghrib = try #require(times.first { $0.name == .maghrib })
        #expect(settings.upcomingPrayers(after: dhuhr.date).map(\.name) == [.maghrib, .fajr, .dhuhr])
        #expect(settings.nextPrayer(after: dhuhr.date)?.name == .maghrib)
        #expect(settings.nextPrayer(after: maghrib.date)?.name == .fajr)
        #expect(settings.upcomingPrayers(after: date, limit: 0).isEmpty)
        let watch = try WatchSettings.decode(WatchSettings(prayers: settings, calendar: .init(timeZoneID: location.timeZoneID)).encoded())
        #expect(watch.prayers.nextPrayer(after: dhuhr.date)?.date == settings.nextPrayer(after: dhuhr.date)?.date)
        #expect(watch.prayers.nextPrayer(after: maghrib.date)?.name == .fajr)
    }

    @Test func invalidLocationIsRejected() throws {
        var settings = WatchSettings(prayers: .init(location: location, method: .tehran, asrRule: .standard, hiddenPrayers: []), calendar: .init())
        settings.prayers.location = .init(latitude: 100, longitude: 39, name: "Invalid", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        #expect(throws: (any Error).self) { try WatchSettings.decode(settings.encoded()) }
    }
}
