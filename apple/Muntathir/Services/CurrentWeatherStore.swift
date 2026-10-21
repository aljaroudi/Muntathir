import CoreLocation
import Foundation
import Observation
import WeatherKit

struct WeatherReading: Sendable {
    let temperature: Measurement<UnitTemperature>
    let apparentTemperature: Measurement<UnitTemperature>
    let condition: String
    let symbol: String
    let date: Date
    let attribution: WeatherAttribution?

    func temperature(feelsLike: Bool) -> Measurement<UnitTemperature> {
        feelsLike ? apparentTemperature : temperature
    }
}

@MainActor @Observable final class CurrentWeatherStore {
    private(set) var reading: WeatherReading?
    private(set) var isLoading = false
    private(set) var failed = false
    private var location: SavedLocation?
    private var fetchedAt: Date?
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private let fetch: (SavedLocation) async throws -> WeatherReading

    init(fetch: @escaping (SavedLocation) async throws -> WeatherReading = CurrentWeatherStore.fetchWeather) {
        self.fetch = fetch
    }

    static func fetchWeather(_ location: SavedLocation) async throws -> WeatherReading {
        let service = WeatherService.shared
        async let current = service.weather(for: CLLocation(latitude: location.latitude, longitude: location.longitude), including: .current)
        async let attribution = service.attribution
        let weather = try await current
        return try await WeatherReading(temperature: weather.temperature, apparentTemperature: weather.apparentTemperature,
                                        condition: weather.condition.description, symbol: weather.symbolName,
                                        date: weather.date, attribution: attribution)
    }

    func refresh(location newLocation: SavedLocation?, now: Date = .now, force: Bool = false) async {
        if location != newLocation {
            task?.cancel()
            requestID = UUID()
            location = newLocation
            reading = nil
            fetchedAt = nil
            isLoading = false
            failed = false
        }
        guard let newLocation else { return }
        guard !isLoading, force || fetchedAt == nil || now.timeIntervalSince(fetchedAt!) >= 900 else { return }
        let id = UUID()
        requestID = id
        isLoading = true
        failed = false
        let work = Task { [weak self, fetch] in
            do {
                let result = try await fetch(newLocation)
                guard let self, requestID == id, !Task.isCancelled else { return }
                reading = result
                fetchedAt = now
                isLoading = false
            } catch {
                guard let self, requestID == id, !Task.isCancelled else { return }
                failed = true
                isLoading = false
            }
        }
        task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if requestID == id {
            isLoading = false
        }
    }
}
