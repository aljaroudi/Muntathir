import SwiftUI

struct WeatherAttributionLink: View {
    var legalPageURL: URL?
    let size: CGSize

    static let fallbackLegalPageURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!

    var body: some View {
        Link(destination: legalPageURL ?? Self.fallbackLegalPageURL) {
            Image("WeatherAttribution")
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel("Apple Weather attribution")
        .accessibilityIdentifier("weather-attribution")
    }
}
