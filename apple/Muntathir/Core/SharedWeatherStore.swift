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

    /// Both weather widgets reload together, so concurrent callers share one WeatherKit request.
    @MainActor private static var inFlight: [SavedLocation: Task<WeatherReading?, Never>] = [:]

    /// Returns a fresh reading, fetching at most once per 15 minutes. With `backoff`, a failure in the
    /// last 5 minutes from any process skips the fetch; the app passes `false` because it throttles itself.
    @MainActor static func refresh(for location: SavedLocation, at date: Date = .now, backoff: Bool = true,
                                   defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID),
                                   fetch: @escaping (SavedLocation) async throws -> WeatherReading = WeatherReading.fetch) async -> WeatherReading?
    {
        let cached = read(for: location, at: date, from: defaults)
        if let cached, date.timeIntervalSince(cached.date) < 900 {
            return cached
        }
        if let running = inFlight[location] {
            return await running.value ?? cached
        }
        // Bound retries across timeline reloads, including failures without a usable reading.
        if backoff, let data = defaults?.data(forKey: attemptKey),
           let attempt = try? JSONDecoder().decode(Attempt.self, from: data),
           attempt.location == location, (0 ..< 300).contains(date.timeIntervalSince(attempt.date))
        {
            return cached
        }
        let task = Task { () -> WeatherReading? in
            do {
                let reading = try await fetch(location)
                write(reading, for: location, to: defaults)
                return reading
            } catch {
                // Recorded only on failure, so a fetch killed mid-flight doesn't block other callers.
                defaults?.set(try? JSONEncoder().encode(Attempt(location: location, date: date)), forKey: attemptKey)
                let failure = error as NSError
                Logger(subsystem: "com.aljaroudi.Muntathir", category: "CalendarWeather")
                    .error("Weather refresh failed: \(failure.domain, privacy: .public) (\(failure.code))")
                return nil
            }
        }
        inFlight[location] = task
        defer { inFlight[location] = nil }
        return await task.value ?? cached
    }

    static func write(_ reading: WeatherReading, for location: SavedLocation,
                      to defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID))
    {
        guard let data = try? JSONEncoder().encode(Snapshot(location: location, reading: reading)) else { return }
        defaults?.set(data, forKey: key)
    }
}
