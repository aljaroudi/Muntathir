import Foundation
@testable import Muntathir
import Testing

struct SolarArcMarkerTests {
    private let location = SavedLocation(latitude: 0, longitude: 0, name: "Equator", countryCode: "", timeZoneID: "GMT")

    private func time(_ hour: Int) -> Date {
        Date(timeIntervalSince1970: 1_773_964_800).addingTimeInterval(Double(hour) * 3600) // 2026-03-20 UTC
    }

    @Test func visibleScheduleDeterminesPastUpcomingAndFuture() {
        let prayers: [PrayerMoment] = [
            .init(name: .fajr, date: time(5)), .init(name: .dhuhr, date: time(12)),
            .init(name: .asr, date: time(15)), .init(name: .isha, date: time(20)),
        ]
        let markers = SolarArcMarker.make(prayers: prayers, now: time(10), location: location)
        #expect(markers.map(\.name) == [.dhuhr, .asr])
        #expect(markers.first?.state == .upcoming)
        #expect(markers.last?.state == .future)
        let later = SolarArcMarker.make(prayers: prayers, now: time(12), location: location)
        #expect(later.first?.state == .past)
        #expect(later.last?.state == .upcoming)
        #expect(markers[0].progress < markers[1].progress)
    }

    @Test func hiddenTimesAreAbsentAndNextOffPathDoesNotPromoteAnotherMarker() {
        let prayers: [PrayerMoment] = [.init(name: .fajr, date: time(5)), .init(name: .asr, date: time(15))]
        let beforeDawn = SolarArcMarker.make(prayers: prayers, now: time(4), location: location)
        #expect(beforeDawn.map(\.name) == [.asr])
        #expect(beforeDawn.first?.state == .future)
        let daytime = SolarArcMarker.make(prayers: prayers, now: time(10), location: location)
        #expect(daytime.first?.state == .upcoming)
    }

    @Test func roundedHorizonTimesStayAtEndpoints() {
        let prayers: [PrayerMoment] = [.init(name: .sunrise, date: time(6)), .init(name: .sunset, date: time(18))]
        let markers = SolarArcMarker.make(prayers: prayers, now: time(12), location: location)
        #expect(markers.map(\.progress) == [0, 1])
        #expect(markers.map(\.state) == [.past, .upcoming])
        #expect(SolarArcMarker.make(prayers: [], now: time(12), location: location).isEmpty)
    }
}
