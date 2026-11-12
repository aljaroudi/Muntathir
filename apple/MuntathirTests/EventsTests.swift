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
}
