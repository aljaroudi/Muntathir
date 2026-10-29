import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import WeatherKit
import Vision

struct WidgetDateCardTests {
    @MainActor @Test(arguments: ["en_GB", "ar_SA@numbers=latn"], [158.0, 170.0])
    func combinedCalendarWeather(language: String, width: Double) throws {
        let date = Date(timeIntervalSince1970: 1_793_183_400)
        let weather = WeatherReading(temperature: .init(value: 30, unit: .celsius),
            apparentTemperature: .init(value: 32, unit: .celsius), condition: "Rain",
            weatherCondition: .rain, date: date, attribution: nil)
        let renderer = ImageRenderer(content: CalendarWeatherCard(date: date,
            settings: .init(timeZoneID: "Asia/Riyadh"), weather: weather)
            .padding(16).frame(width: width, height: width).background(.white)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.layoutDirection, language.hasPrefix("ar") ? .rightToLeft : .leftToRight))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        try Attachment.record(#require(image.pngData()), named: "combined-\(language)-\(width).png")
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.35)
        try VNImageRequestHandler(cgImage: #require(image.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        #expect(text.contains("30"), "Complete temperature must fit in the footer: \(text)")
    }

    @MainActor @Test(arguments: ["en_US", "ar_SA@numbers=latn"], [true, false])
    func separateWeatherWidget(language: String, hijri: Bool) throws {
        let date = Date(timeIntervalSince1970: 1_793_183_400)
        let weather = WeatherReading(temperature: .init(value: 30, unit: .celsius),
                                     apparentTemperature: .init(value: 32, unit: .celsius),
                                     condition: "Clear", weatherCondition: .clear, date: date, attribution: nil)
        let renderer = ImageRenderer(content: WeatherDateCard(date: date,
            settings: .init(timeZoneID: "Asia/Riyadh"), weather: weather, usesHijriDate: hijri)
            .padding(16).frame(width: 158, height: 158).background(.white)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.layoutDirection, language.hasPrefix("ar") ? .rightToLeft : .leftToRight))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        try Attachment.record(#require(image.pngData()), named: "weather-\(language)-\(hijri).png")
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: #require(image.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        #expect(text.contains(language == "en_US" ? "86" : "30"), "Full temperature must fit: \(text)")
        #expect(text.contains(hijri ? "17" : "28"), "The selected calendar's day must be displayed: \(text)")
        #expect(text.contains("/"), "The date must remain numeric and compact: \(text)")
    }

    @MainActor @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5])
    func compactLayouts(typeSize: DynamicTypeSize) throws {
        let date = Date(timeIntervalSince1970: 1_792_578_600)
        let location = SavedLocation(latitude: 21.42, longitude: 39.82, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
        let settings = WidgetCalendarSettings(timeZoneID: location.timeZoneID)
        for language in ["en_GB", "ar_SA"] {
            for dark in [false, true] {
                let card = CalendarCard(date: date, settings: settings)
                let renderer = ImageRenderer(content: card.padding(16).frame(width: 170, height: 170)
                    .background(Color(.systemBackground)).clipShape(.rect(cornerRadius: 22))
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.layoutDirection, language == "ar_SA" ? .rightToLeft : .leftToRight)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 3
                let image = try #require(renderer.uiImage)
                try Attachment.record(#require(image.pngData()), named: "calendar-\(language)-\(dark ? "dark" : "light")-\(typeSize).png")
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
