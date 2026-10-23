import CoreLocation
import Foundation
import WeatherKit

struct WeatherReading: Codable, Sendable {
    let temperature: Measurement<UnitTemperature>
    let apparentTemperature: Measurement<UnitTemperature>
    let condition: String
    let weatherCondition: WeatherCondition?
    let date: Date
    let attribution: Attribution?

    struct Attribution: Codable, Sendable {
        let legalPageURL: URL
        // Variants are named for the background: light uses black artwork, dark uses white.
        let combinedMarkLightURL: URL
        let combinedMarkDarkURL: URL

        init(_ attribution: WeatherAttribution) {
            legalPageURL = attribution.legalPageURL
            combinedMarkLightURL = attribution.combinedMarkLightURL
            combinedMarkDarkURL = attribution.combinedMarkDarkURL
        }
    }

    func temperature(feelsLike: Bool) -> Measurement<UnitTemperature> {
        feelsLike ? apparentTemperature : temperature
    }

    func isCurrent(at date: Date) -> Bool {
        date.timeIntervalSince(self.date) < 3600
    }

    static func fetch(_ location: SavedLocation) async throws -> WeatherReading {
        let service = WeatherService.shared
        async let current = service.weather(for: CLLocation(latitude: location.latitude, longitude: location.longitude), including: .current)
        async let attribution = service.attribution
        let weather = try await current
        return try await WeatherReading(temperature: weather.temperature, apparentTemperature: weather.apparentTemperature,
                                        condition: weather.condition.description, weatherCondition: weather.condition,
                                        date: weather.date, attribution: Attribution(attribution))
    }
}
