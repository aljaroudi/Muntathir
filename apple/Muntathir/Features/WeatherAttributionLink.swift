import SwiftUI

struct WeatherAttributionLink: View {
    var legalPageURL: URL?
    let size: CGSize
    @Environment(\.locale) private var locale

    static let fallbackLegalPageURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!

    nonisolated static func assetName(for locale: Locale) -> String {
        let languages = ["en", "ar", "de", "es", "fr", "id", "it", "ja", "ms", "ru", "tr", "zh-Hans", "zh-Hant"]
        let language = Bundle.preferredLocalizations(from: languages, forPreferences: [locale.identifier]).first ?? "en"
        return "WeatherAttribution-\(language)"
    }

    var body: some View {
        Link(destination: legalPageURL ?? Self.fallbackLegalPageURL) {
            Image(Self.assetName(for: locale))
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel("Apple Weather attribution")
        .accessibilityIdentifier("weather-attribution")
    }
}
