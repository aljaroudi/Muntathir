import Foundation
import OSLog

/// The app and widget share the last successful reading for the selected location.
enum SharedWeatherStore {
    private struct Snapshot: Codable {
        let location: SavedLocation
        let reading: WeatherReading
    }

    private struct Attempt: Codable {
        let location: SavedLocation
        let date: Date
    }

    private static let key = "widgetWeather.v1"
    private static let attemptKey = "widgetWeather.attempt.v1"

    static func read(for location: SavedLocation, at date: Date = .now,
                     from defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID)) -> WeatherReading?
    {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.location == location, snapshot.reading.isCurrent(at: date) else { return nil }
        return snapshot.reading
    }

    static func refresh(for location: SavedLocation, at date: Date = .now,
                        defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID),
                        fetch: (SavedLocation) async throws -> WeatherReading = WeatherReading.fetch) async -> WeatherReading?
    {
        let cached = read(for: location, at: date, from: defaults)
        if let cached, date.timeIntervalSince(cached.date) < 900 {
            return cached
        }
        // Bound retries across timeline reloads, including failures without a usable reading.
        if let data = defaults?.data(forKey: attemptKey),
           let attempt = try? JSONDecoder().decode(Attempt.self, from: data),
           attempt.location == location, (0 ..< 300).contains(date.timeIntervalSince(attempt.date))
        {
            return cached
        }
        defaults?.set(try? JSONEncoder().encode(Attempt(location: location, date: date)), forKey: attemptKey)
        do {
            let reading = try await fetch(location)
            write(reading, for: location, to: defaults)
            return reading
        } catch {
            let failure = error as NSError
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "CalendarWeather")
                .error("Weather refresh failed: \(failure.domain, privacy: .public) (\(failure.code))")
            return cached
        }
    }

    static func write(_ reading: WeatherReading, for location: SavedLocation,
                      to defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID))
    {
        guard let data = try? JSONEncoder().encode(Snapshot(location: location, reading: reading)) else { return }
        defaults?.set(data, forKey: key)
    }
}
