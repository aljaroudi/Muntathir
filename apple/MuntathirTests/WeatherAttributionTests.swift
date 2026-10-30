import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import UIKit

struct WeatherAttributionTests {
    @Test(arguments: ["en", "ar", "de", "es", "fr", "id", "it", "ja", "ms", "ru", "tr", "zh-Hans", "zh-Hant"])
    func matchingArtwork(language: String) {
        #expect(WeatherAttributionLink.assetName(for: Locale(identifier: language)) == "WeatherAttribution-\(language)")
    }

    @Test(arguments: ["fa", "ur", "zz"])
    func unsupportedLanguageUsesEnglish(language: String) {
        #expect(WeatherAttributionLink.assetName(for: Locale(identifier: language)) == "WeatherAttribution-en")
    }

    @Test func regionalLanguages() {
        for (locale, language) in [("en_GB", "en"), ("ar_SA", "ar"), ("zh_CN", "zh-Hans"), ("zh_TW", "zh-Hant"), ("zh_HK", "zh-Hant")] {
            #expect(WeatherAttributionLink.assetName(for: Locale(identifier: locale)) == "WeatherAttribution-\(language)")
        }
    }

    @MainActor @Test func bundledMarksRenderInBothAppearances() throws {
        for language in ["en", "ar", "de", "es", "fa", "fr", "id", "it", "ja", "ms", "ru", "tr", "ur", "zh-Hans", "zh-Hant"] {
            let name = WeatherAttributionLink.assetName(for: Locale(identifier: language))
            let light = try #require(UIImage(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .light)))
            let dark = try #require(UIImage(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .dark)))
            #expect(light.size.width > 0 && light.size.height > 0)
            #expect(light.pngData() != dark.pngData())
        }
    }

    @MainActor @Test func languageChangesWithoutWeatherRefreshOrNetwork() throws {
        let link = WeatherAttributionLink(legalPageURL: nil, size: CGSize(width: 86, height: 16))
        #expect(link.legalPageURL == nil)
        #expect(WeatherAttributionLink.fallbackLegalPageURL.absoluteString == "https://developer.apple.com/weatherkit/data-source-attribution/")
        let supplied = try #require(URL(string: "https://example.invalid/legal"))
        #expect(WeatherAttributionLink(legalPageURL: supplied, size: link.size).legalPageURL == supplied)
        for scheme in [ColorScheme.light, .dark] {
            func render(_ language: String) throws -> Data {
                let renderer = ImageRenderer(content: link
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.colorScheme, scheme))
                return try #require(renderer.uiImage?.pngData())
            }
            let arabic = try render("ar")
            #expect(try render("en") != arabic)
            #expect(try render("ar") == arabic)
        }
    }
}
