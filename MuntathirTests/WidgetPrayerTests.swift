import Foundation
import Testing
import SwiftUI
@testable import Muntathir

struct WidgetPrayerTests {
    let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
    @Test func hiddenPrayersAndNextDayRollover() throws {
        let settings = WidgetPrayerSettings(location: location, method: .tehran, asrRule: .standard, hiddenPrayers: [.asr, .isha])
        let day = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        let prayers = settings.prayers(on: day)
        #expect(prayers.map(\.name) == [.fajr, .sunrise, .dhuhr, .sunset, .maghrib, .midnight])
        let maghrib = try #require(prayers.first { $0.name == .maghrib })
        let next = try #require(settings.nextPrayer(after: maghrib.date))
        #expect(next.name == .fajr)
        #expect(CivilDate(next.date, in: location.timeZone) == CivilDate(year: 2026, month: 10, day: 19))
        let dates = settings.timelineDates(from: day)
        #expect(dates == dates.sorted())
        #expect(dates.contains(maghrib.date))
        #expect(dates.contains(try #require(CivilDate(year: 2026, month: 10, day: 19).date(in: location.timeZone))))
    }
    @Test func missingLocationDoesNotInventTimes() {
        let settings = WidgetPrayerSettings(location: nil, method: .tehran, asrRule: .standard, hiddenPrayers: [])
        #expect(settings.prayers(on: .now).isEmpty)
        #expect(settings.nextPrayer(after: .now) == nil)
    }
    @Test func sharedSettingsRoundTripAndOnlyReloadOnChange() throws {
        let suite = "Widgets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WidgetPrayerSettings(location: location, method: .jafari, asrRule: .standard, hiddenPrayers: [.isha])
        #expect(WidgetPrayerStore.write(settings, to: defaults))
        #expect(WidgetPrayerStore.read(from: defaults) == settings)
        #expect(!WidgetPrayerStore.write(settings, to: defaults))
        settings.location = nil
        #expect(WidgetPrayerStore.write(settings, to: defaults))
        #expect(WidgetPrayerStore.read(from: defaults)?.location == nil)
    }
    @Test func countdownUsesHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        let style = PrayerCountdownFormat(target: now.addingTimeInterval(4380), locale: Locale(identifier: "en_US"))
        let text = String(style.format(now).characters)
        #expect(text.contains("1"))
        #expect(text.contains("13"))
        #expect(text == "1h 13m")
        #expect(style.discreteInput(after: now) == now.addingTimeInterval(60))
        #expect(style.discreteInput(after: style.target) == nil)
        #expect(String(style.format(style.target.addingTimeInterval(60)).characters) == "0m")
    }
}

struct AdditionalPrayerTimesTests {
    @Test(arguments: [PrayerMethod.jafari, .tehran, .ummAlQura])
    func midnightUsesSunsetAndNextFajr(method: PrayerMethod) throws {
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let day = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone))
        let tomorrow = try #require(CivilDate(year: 2026, month: 10, day: 19).date(in: location.timeZone))
        let today = PrayerCalculator.times(on: day, location: location, method: method)
        let next = PrayerCalculator.times(on: tomorrow, location: location, method: method)
        let sunset = try #require(today.first { $0.name == .sunset })
        let midnight = try #require(today.first { $0.name == .midnight })
        let fajr = try #require(next.first { $0.name == .fajr })
        let expected = sunset.date.addingTimeInterval(fajr.date.timeIntervalSince(sunset.date) / 2)
        #expect(abs(midnight.date.timeIntervalSince(expected)) <= 30)
        if method == .tehran || method == .jafari {
            #expect(sunset.date < (try #require(today.first { $0.name == .maghrib })).date)
        }
        #expect(!PrayerName.notifiable.contains(.sunset))
        #expect(!PrayerName.notifiable.contains(.midnight))
    }

    @Test func coreTimesCannotBeHiddenEvenByStoredSettings() {
        var preferences = Preferences()
        preferences.hiddenPrayers = Set(PrayerName.allCases)
        #expect(PrayerName.allCases.filter { preferences.isVisible($0) } == [.fajr, .dhuhr, .maghrib])
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let widget = WidgetPrayerSettings(location: location, method: .tehran, asrRule: .standard, hiddenPrayers: preferences.hiddenPrayers)
        #expect(widget.prayers(on: Date()).map(\.name) == [.fajr, .dhuhr, .maghrib])
    }
}

struct CompactWidgetTests {
    @Test func upcomingTimesAreLimitedAndRollIntoTomorrow() throws {
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let settings = WidgetPrayerSettings(location: location, method: .tehran, asrRule: .standard,
                                           hiddenPrayers: [.sunrise, .asr, .sunset, .isha, .midnight])
        let date = try #require(CivilDate(year: 2026, month: 10, day: 18).date(in: location.timeZone)).addingTimeInterval(20 * 3600)
        let upcoming = settings.upcomingTimes(after: date)
        #expect(upcoming.map(\.name) == [.fajr, .dhuhr, .maghrib])
        #expect(upcoming.allSatisfy { $0.date > date })
        #expect(settings.upcomingTimes(after: date, limit: 2).count == 2)
        #expect(settings.upcomingTimes(after: date, limit: 0).isEmpty)
    }
}

struct CalendarWidgetTests {
    @Test func correctionsSurviveSharingAndReset() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let baseline = try CalendarEngine(timeZone: zone)
        let month = HijriMonth(year: 1448, month: 1)
        let start = baseline.addingDays(1, to: baseline.start(of: month))
        let correction = MonthCorrection(month: month, start: CivilDate(start, in: zone), provenance: .manual, sourceID: nil)
        let settings = WidgetCalendarSettings(timeZoneID: zone.identifier, manual: [correction])
        let suite = "CalendarWidget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(settings.write(to: defaults))
        let restored = WidgetCalendarSettings.read(from: defaults)
        #expect(restored.engine.resolve(start).day == 1)
        #expect(restored.engine.resolve(start).provenance == .manual)
        #expect(!settings.write(to: defaults))
        #expect(WidgetCalendarSettings(timeZoneID: zone.identifier).write(to: defaults))
        #expect(WidgetCalendarSettings.read(from: defaults).engine.resolve(start).day == 2)
    }

    @Test func timelineUsesLocalMidnightAcrossDST() throws {
        let settings = WidgetCalendarSettings(timeZoneID: "America/New_York")
        let date = try #require(CivilDate(year: 2026, month: 3, day: 8).date(in: settings.zone))
        let dates = settings.timelineDates(from: date)
        #expect(dates.count == 8)
        #expect(dates[1].timeIntervalSince(date) == 23 * 3600)
        #expect(dates.dropFirst().allSatisfy { settings.engine.gregorian.component(.hour, from: $0) == 0 })
        #expect(WidgetCalendarSettings().timelineDates(from: date).count == 8)
    }
}
