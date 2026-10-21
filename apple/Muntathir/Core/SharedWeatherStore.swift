import Foundation
import OSLog

/// The app and widget share the last successful reading for the selected location.
enum SharedWeatherStore {
    private struct Snapshot: Codable {
        let location: SavedLocation
        let reading: WeatherReading
    }

    private static let key = "widgetWeather.v1"

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
        do {
            let reading = try await fetch(location)
            write(reading, for: location, to: defaults)
            return reading
        } catch {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "CalendarWeather")
                .error("Widget weather refresh failed: \(String(describing: error))")
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
