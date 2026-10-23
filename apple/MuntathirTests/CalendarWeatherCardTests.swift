import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import WeatherKit

struct CalendarWeatherCardTests {
    @MainActor @Test func compactLayouts() throws {
        let date = Date(timeIntervalSince1970: 1_792_578_600)
        let location = SavedLocation(latitude: 21.42, longitude: 39.82, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let settings = WidgetCalendarSettings(timeZoneID: location.timeZoneID)
        let weather = WeatherReading(temperature: .init(value: 24, unit: .celsius), apparentTemperature: .init(value: 26, unit: .celsius),
                                     condition: "Rain", weatherCondition: .rain, date: date, attribution: nil)
        for language in ["en_GB", "ar_SA"] {
            for dark in [false, true] {
                let card = CalendarWeatherCard(date: date, settings: settings, location: location, weather: weather)
                let renderer = ImageRenderer(content: card.padding(16).frame(width: 170, height: 170)
                    .background(card.surface).clipShape(.rect(cornerRadius: 22))
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.layoutDirection, language == "ar_SA" ? .rightToLeft : .leftToRight)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 3
                let image = try #require(renderer.uiImage)
                try Attachment.record(#require(image.pngData()), named: "calendar-\(language)-\(dark ? "dark" : "light").png")
                #expect(image.size.width == 170)
                #expect(image.size.height == 170)
            }
        }
    }

    @MainActor @Test func freshWeatherAndAttributionStayVisibleAfterRefreshFailure() async throws {
        let date = Date.now
        let location = SavedLocation(latitude: 21.42, longitude: 39.82, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let attribution = try JSONDecoder().decode(WeatherReading.Attribution.self, from: Data(#"{"legalPageURL":"https://example.invalid/legal","combinedMarkLightURL":"file:///missing-light.png","combinedMarkDarkURL":"file:///missing-dark.png"}"#.utf8))
        var calls = 0
        let weather = CurrentWeatherStore(publish: { _, _ in }) { _ in
            calls += 1
            if calls > 1 {
                throw URLError(.notConnectedToInternet)
            }
            return WeatherReading(temperature: .init(value: 24, unit: .celsius), apparentTemperature: .init(value: 26, unit: .celsius),
                                  condition: "Clear", weatherCondition: .clear, date: date, attribution: attribution)
        }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        model.select(location)
        func renderedCards() throws -> Data {
            let renderer = ImageRenderer(content: TodayInfoCards(date: date, skyBackground: false, weather: weather, sun: nil, moon: nil)
                .frame(width: 380, height: 500).environment(model))
            return try #require(renderer.uiImage?.pngData())
        }
        await weather.refresh(location: location, now: date)
        let original = try renderedCards()
        await weather.refresh(location: location, now: date.addingTimeInterval(901), force: true)
        #expect(weather.failed)
        #expect(weather.reading?.attribution?.legalPageURL == attribution.legalPageURL)
        #expect(try renderedCards() == original)
    }
}
