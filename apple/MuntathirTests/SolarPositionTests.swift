import CoreGraphics
import Foundation
@testable import Muntathir
import Testing

struct SolarPositionTests {
    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    @Test func matchesNRELReferenceExample() throws {
        // NREL SPA report example: 2003-10-17, 12:30:30 MST, 39.742476 N / 105.1786 W.
        // https://www.nrel.gov/docs/fy08osti/34302.pdf (zenith 50.11162°, azimuth 194.34024°).
        let sun = try #require(SolarPosition.calculate(at: date("2003-10-17T19:30:30Z"), latitude: 39.742476, longitude: -105.1786))
        #expect(abs(sun.apparentElevation - (90 - 50.11162)) < 0.05)
        #expect(abs(sun.azimuth - 194.34024) < 0.05)
        #expect(sun.isRising == false)
    }

    @Test(arguments: ["2026-06-21T12:00:00Z", "2026-12-21T12:00:00Z"])
    func polarSeasonsRemainFinite(instant: String) throws {
        let north = try #require(SolarPosition.calculate(at: date(instant), latitude: 90, longitude: 0))
        let south = try #require(SolarPosition.calculate(at: date(instant), latitude: -90, longitude: 0))
        #expect(north.elevation.isFinite)
        #expect(south.azimuth.isFinite)
        #expect(abs(north.elevation + south.elevation) < 0.001)
        #expect(abs(abs(north.elevation) - 23.44) < 0.1)
        #expect((north.elevation > 0) == instant.contains("06-21"))
    }

    @Test func dateLineAndTimeZoneDoNotChangeAnInstant() throws {
        let instant = try date("2026-03-20T00:00:00Z")
        let east = try #require(SolarPosition.calculate(at: instant, latitude: 0, longitude: 180))
        let west = try #require(SolarPosition.calculate(at: instant, latitude: 0, longitude: -180))
        #expect(abs(east.elevation - west.elevation) < 0.00001)
        #expect(abs(east.azimuth - west.azimuth) < 0.00001)
        #expect(east.elevation > 87)
        let sameInstant = try date("2026-03-20T03:00:00+03:00")
        #expect(instant == sameInstant)
    }

    @Test func sunriseIsEastAndSunsetIsWest() throws {
        let morning = try #require(SolarPosition.calculate(at: date("2026-03-20T06:07:00Z"), latitude: 0, longitude: 0))
        let evening = try #require(SolarPosition.calculate(at: date("2026-03-20T18:07:00Z"), latitude: 0, longitude: 0))
        #expect(abs(morning.azimuth - 90) < 1)
        #expect(abs(evening.azimuth - 270) < 1)
        #expect(abs(morning.elevation) < 1)
        #expect(morning.apparentElevation > morning.elevation)
        #expect(morning.isRising)
        #expect(evening.isRising == false)
    }

    @Test func invalidInputsReturnNoSky() {
        #expect(SolarPosition.calculate(at: .now, latitude: .nan, longitude: 0) == nil)
        #expect(SolarPosition.calculate(at: .now, latitude: 91, longitude: 0) == nil)
        #expect(SolarPosition.calculate(at: .now, latitude: 0, longitude: .infinity) == nil)
        #expect(SolarPosition.calculate(at: .now, latitude: 0, longitude: 181) == nil)
    }

    @Test func daytimeProgressRunsFromLeftToRightAndDisappearsAtNight() throws {
        var previous = -1.0
        for hour in 7 ... 17 {
            let sun = try #require(SolarPosition.calculate(at: date(String(format: "2026-03-20T%02d:00:00Z", hour)), latitude: 0, longitude: 0))
            let progress = try #require(sun.daylightProgress)
            #expect(progress > previous)
            #expect((0 ... 1).contains(progress))
            previous = progress
        }
        let noon = try #require(SolarPosition.calculate(at: date("2026-03-20T12:07:00Z"), latitude: 0, longitude: 0))
        #expect(try abs(#require(noon.daylightProgress) - 0.5) < 0.01)
        let night = try #require(SolarPosition.calculate(at: date("2026-03-20T00:00:00Z"), latitude: 0, longitude: 0))
        #expect(night.daylightProgress == nil)
    }

    @Test func arcKeepsSunWithinItsReservedBand() {
        let bounds = CGRect(x: 36, y: 24, width: 330, height: 100)
        #expect(SolarArcLayout.point(progress: 0, in: bounds) == CGPoint(x: 36, y: 124))
        #expect(SolarArcLayout.point(progress: 0.5, in: bounds) == CGPoint(x: 201, y: 24))
        #expect(abs(SolarArcLayout.point(progress: 1, in: bounds).y - 124) < 0.001)
        for step in 0 ... 100 {
            let point = SolarArcLayout.point(progress: Double(step) / 100, in: bounds)
            #expect(point.x >= bounds.minX && point.x <= bounds.maxX)
            #expect(point.y >= bounds.minY && point.y <= bounds.maxY)
        }
    }

    @Test func polarDayStaysVisibleAndPolarNightHasNoSun() throws {
        for hour in [0, 6, 12, 18] {
            let summer = try #require(SolarPosition.calculate(at: date(String(format: "2026-06-21T%02d:00:00Z", hour)), latitude: 90, longitude: 0))
            let winter = try #require(SolarPosition.calculate(at: date(String(format: "2026-12-21T%02d:00:00Z", hour)), latitude: 90, longitude: 0))
            #expect(summer.daylightProgress != nil)
            #expect(winter.daylightProgress == nil)
        }
    }

    @Test func retiredTiltPreferenceDoesNotBreakSavedSettings() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"followsSkyTilt":true,"prayerMethod":"jafari"}"#.utf8))
        #expect(preferences.prayerMethod == .jafari)
        #expect(try String(decoding: JSONEncoder().encode(preferences), as: UTF8.self).contains("followsSkyTilt") == false)
    }
}
