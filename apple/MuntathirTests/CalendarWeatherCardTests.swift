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
}
