import Foundation
@testable import Muntathir
import Testing

struct MoonPositionTests {
    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    @Test func matchesPublishedTopocentricExample() throws {
        // Schlyter's 1990-04-19 example at 60 N, 15 E: topocentric RA 310.0017°, dec -19.8790°,
        // LST 221.8388°. Converted to horizontal coordinates independently.
        // https://www.stjarnhimlen.se/comp/tutorial.html#9
        let moon = try #require(MoonPosition.calculate(at: date("1990-04-19T00:00:00Z"), latitude: 60, longitude: 15))
        #expect(abs(moon.elevation - -16.2247) < 0.05)
        #expect(abs(moon.azimuth - 101.7863) < 0.05)
        #expect(moon.visibleProgress == nil)
    }

    @Test(arguments: [
        ("2024-04-08T18:21:00Z", 0.0),
        ("2024-04-15T19:13:00Z", 0.5),
        ("2024-04-23T23:49:00Z", 1.0),
        ("2024-04-02T03:15:00Z", 0.5),
    ])
    func matchesIndependentPhaseFixtures(instant: String, fraction: Double) throws {
        // Fred Espenak's phase table: https://www.astropixels.com/almanac/almanac21/almanac2024gmt.html
        let moon = try #require(MoonPosition.calculate(at: date(instant), latitude: 21.4225, longitude: 39.8262))
        #expect(abs(moon.illuminatedFraction - fraction) < 0.005)
        if instant.contains("04-15") {
            #expect(moon.isWaxing)
        }
        if instant.contains("04-02") {
            #expect(!moon.isWaxing)
        }
    }

    @Test func locationChangesPositionButNotPhase() throws {
        let instant = try date("2026-10-21T16:00:00Z")
        let mecca = try #require(MoonPosition.calculate(at: instant, latitude: 21.4225, longitude: 39.8262))
        let opposite = try #require(MoonPosition.calculate(at: instant, latitude: -21.4225, longitude: -140.1738))
        #expect(mecca.visibleProgress != nil)
        #expect(opposite.visibleProgress == nil)
        #expect(mecca.illuminatedFraction == opposite.illuminatedFraction)
        #expect(mecca.isWaxing == opposite.isWaxing)
    }

    @Test(arguments: [-90.0, -33.9, 0, 21.4, 90])
    func dailyVisibilityAndProgressStayValid(latitude: Double) throws {
        let start = try date("2026-10-21T00:00:00Z")
        for hour in 0 ..< 48 {
            let instant = start.addingTimeInterval(Double(hour) * 3600)
            let east = try #require(MoonPosition.calculate(at: instant, latitude: latitude, longitude: 180))
            let west = try #require(MoonPosition.calculate(at: instant, latitude: latitude, longitude: -180))
            #expect(east.elevation.isFinite && east.azimuth.isFinite)
            #expect(abs(east.elevation - west.elevation) < 0.00001)
            #expect((east.visibleProgress != nil) == (east.elevation >= 0))
            if let progress = east.visibleProgress {
                #expect((0 ... 1).contains(progress))
            }
        }
    }

    @Test func invalidCoordinatesOrDateHaveNoMoon() {
        #expect(MoonPosition.calculate(at: .now, latitude: .nan, longitude: 0) == nil)
        #expect(MoonPosition.calculate(at: .now, latitude: 91, longitude: 0) == nil)
        #expect(MoonPosition.calculate(at: .now, latitude: 0, longitude: .infinity) == nil)
        #expect(MoonPosition.calculate(at: .now, latitude: 0, longitude: -181) == nil)
        #expect(MoonPosition.calculate(at: Date(timeIntervalSince1970: .nan), latitude: 0, longitude: 0) == nil)
    }
}
