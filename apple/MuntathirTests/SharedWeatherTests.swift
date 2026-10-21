import Foundation
@testable import Muntathir
import Testing

struct SharedWeatherTests {
    private let location = SavedLocation(latitude: 21.42, longitude: 39.82, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func reading(at date: Date) -> WeatherReading {
        WeatherReading(temperature: .init(value: 24, unit: .celsius), apparentTemperature: .init(value: 26, unit: .celsius),
                       condition: "Rain", weatherCondition: nil, date: date, attribution: nil)
    }

    @Test func appReadingAvoidsIndependentWidgetRequest() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SharedWeatherStore.write(reading(at: now), for: location, to: defaults)
        let result = await SharedWeatherStore.refresh(for: location, at: now, defaults: defaults) { _ in
            Issue.record("Fresh app weather must not require widget WeatherKit authentication")
            throw URLError(.userAuthenticationRequired)
        }
        #expect(result?.temperature.value == 24)
        #expect(result?.apparentTemperature.value == 26)
    }

    @Test func failedRefreshKeepsValidCacheButRejectsExpiredOrWrongLocation() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SharedWeatherStore.write(reading(at: now), for: location, to: defaults)
        let result = await SharedWeatherStore.refresh(for: location, at: now.addingTimeInterval(901), defaults: defaults) { _ in
            throw URLError(.userAuthenticationRequired)
        }
        #expect(result?.date == now)
        let expired = await SharedWeatherStore.refresh(for: location, at: now.addingTimeInterval(3600), defaults: defaults) { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(expired == nil)
        let other = SavedLocation(latitude: 51.5, longitude: 0, name: "London", countryCode: "GB", timeZoneID: "Europe/London")
        #expect(SharedWeatherStore.read(for: other, at: now, from: defaults) == nil)
    }

    @Test func successfulRefreshPublishesReading() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let result = await SharedWeatherStore.refresh(for: location, at: now, defaults: defaults) { _ in reading(at: now) }
        #expect(result?.date == now)
        #expect(SharedWeatherStore.read(for: location, at: now, from: defaults)?.date == now)
    }
}
