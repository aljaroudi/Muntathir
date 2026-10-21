import Foundation
@testable import Muntathir
import Testing
import WeatherKit

@MainActor struct CurrentWeatherTests {
    private let location = SavedLocation(latitude: 21.42, longitude: 39.82, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func reading(_ value: Double = 30) -> WeatherReading {
        WeatherReading(temperature: .init(value: value, unit: .celsius), apparentTemperature: .init(value: 35, unit: .celsius),
                       condition: "Clear", weatherCondition: .clear, date: now, attribution: nil)
    }

    @Test func preferencesAndTemperatureSelection() throws {
        var prefs = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(!prefs.showFeelsLikeTemperature)
        prefs.showFeelsLikeTemperature = true
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs)).showFeelsLikeTemperature)
        #expect(reading().temperature(feelsLike: false).value == 30)
        #expect(reading().temperature(feelsLike: true).value == 35)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let model = AppModel(defaults: defaults, cloud: nil)
        model.update { $0.showFeelsLikeTemperature = true }
        #expect(AppModel(defaults: defaults, cloud: nil).preferences.showFeelsLikeTemperature)
    }

    @Test func throttlesAndKeepsReadingOnFailure() async {
        var calls = 0
        let store = CurrentWeatherStore { _ in
            calls += 1
            if calls > 1 {
                throw URLError(.notConnectedToInternet)
            }
            return reading()
        }
        await store.refresh(location: location, now: now)
        await store.refresh(location: location, now: now.addingTimeInterval(899))
        #expect(calls == 1)
        await store.refresh(location: location, now: now.addingTimeInterval(900))
        #expect(calls == 2)
        #expect(store.failed)
        #expect(store.reading?.temperature.value == 30)
        #expect(!store.isLoading)
        await store.refresh(location: nil)
        #expect(store.reading == nil)
        #expect(!store.failed)
    }

    @Test func ignoresLateResponseFromPreviousLocation() async {
        var pending: CheckedContinuation<WeatherReading, any Error>?
        let store = CurrentWeatherStore { requested in
            if requested == location {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return reading(20)
        }
        let first = Task { await store.refresh(location: location, now: now) }
        while pending == nil {
            await Task.yield()
        }
        let other = SavedLocation(latitude: 51.5, longitude: -0.1, name: "London", countryCode: "GB", timeZoneID: "Europe/London")
        await store.refresh(location: other, now: now)
        pending?.resume(returning: reading())
        await first.value
        #expect(store.reading?.temperature.value == 20)
        #expect(!store.failed)
    }

    @Test func failureCanRetry() async {
        var calls = 0
        let store = CurrentWeatherStore { _ in
            calls += 1
            if calls == 1 {
                throw URLError(.timedOut)
            }
            return reading()
        }
        await store.refresh(location: location, now: now)
        #expect(store.failed && store.reading == nil)
        await store.refresh(location: location, now: now, force: true)
        #expect(store.reading != nil && !store.failed)
    }
}
