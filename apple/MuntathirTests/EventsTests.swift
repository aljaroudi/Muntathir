import Foundation
@testable import Muntathir
import Testing

struct EventsTests {
    @MainActor @Test func allEventsAppearOnceInMonthAndDayOrder() {
        let events = ContentLibrary().events
        #expect(events.isEmpty == false)
        let sections = (1 ... 12).map { EventsView.events(in: $0, from: events) }
        #expect(sections.flatMap(\.self).count == events.count)
        #expect(Set(sections.flatMap(\.self).map(\.id)) == Set(events.map(\.id)))
        for (index, section) in sections.enumerated() {
            #expect(section.allSatisfy { $0.month == index + 1 })
            #expect(section.map(\.day) == section.map(\.day).sorted())
        }
    }

    @MainActor @Test func dayThirtyAndSameDaySourceOrderArePreserved() {
        let events = [
            IslamicEvent(id: "last", month: 2, day: 30, title: ["en": "Last"]),
            IslamicEvent(id: "second", month: 2, day: 1, title: ["en": "Second"]),
            IslamicEvent(id: "first", month: 2, day: 1, title: ["en": "First"]),
            IslamicEvent(id: "other", month: 3, day: 1, title: ["en": "Other"]),
        ]
        #expect(EventsView.events(in: 2, from: events).map(\.id) == ["second", "first", "last"])
        #expect(EventsView.events(in: 1, from: events).isEmpty)
    }

    @Test func upcomingEventFollowsCorrectedDateAndSunsetBoundaries() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
        let month = HijriMonth(year: 1448, month: 8)
        let engine = try CalendarEngine(timeZone: zone, offsets: [.init(month: month, days: 1)])
        let date = engine.addingDays(2, to: engine.start(of: month))
        let preceding = engine.addingDays(-1, to: date)
        let earlier = engine.addingDays(-2, to: date)
        let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: zone.identifier)
        let settings = WidgetPrayerSettings(location: location, method: .jafari, hiddenPrayers: [.sunset])
        let opening = try #require(settings.sunset(on: preceding))
        let closing = try #require(settings.sunset(on: date))
        let library = ContentLibrary()

        for (instant, timing): (Date, ContentLibrary.EventTiming) in [
            (earlier, .countdown(.seconds(opening.timeIntervalSince(earlier)))),
            (preceding, .tonight),
            (opening.addingTimeInterval(-1), .tonight),
            (opening, .tonight),
            (date, .today),
            (closing.addingTimeInterval(-1), .today),
        ] {
            let event = try #require(library.upcomingEvent(on: instant, engine: engine, sunset: settings.sunset(on:)))
            #expect(event.events.map(\.id) == ["husayn-birth", "husayn-enter-mecca"])
            #expect(event.timing == timing)
        }
        let next = try #require(library.upcomingEvent(on: closing, engine: engine, sunset: settings.sunset(on:)))
        #expect(next.events.map(\.id) == ["abbas-birth"])
        #expect(next.timing == .tonight)
    }

    @Test func upcomingEventUsesCivilMidnightWithoutSunset() throws {
        let engine = try CalendarEngine(timeZone: .gmt)
        let date = engine.addingDays(2, to: engine.start(of: .init(year: 1448, month: 8)))
        let earlier = engine.addingDays(-2, to: date)
        let library = ContentLibrary()
        #expect(library.upcomingEvent(on: earlier, engine: engine, sunset: { _ in nil })?.timing == .countdown(.seconds(172_800)))
        #expect(library.upcomingEvent(on: date.addingTimeInterval(-1), engine: engine, sunset: { _ in nil })?.timing == .tomorrow)
        #expect(library.upcomingEvent(on: date, engine: engine, sunset: { _ in nil })?.timing == .today)
        let nextDay = engine.addingDays(1, to: date)
        #expect(library.upcomingEvent(on: nextDay.addingTimeInterval(-1), engine: engine, sunset: { _ in nil })?.events.first?.id == "husayn-birth")
        #expect(library.upcomingEvent(on: nextDay, engine: engine, sunset: { _ in nil })?.events.first?.id == "abbas-birth")
    }
}
