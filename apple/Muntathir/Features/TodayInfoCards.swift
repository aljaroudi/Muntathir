import SwiftUI
import WeatherKit

struct TodayInfoCards: View {
    let date: Date
    let skyBackground: Bool
    let weather: CurrentWeatherStore
    let sun: SolarPosition?
    let moon: MoonPosition?
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var availableWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var minimumWidth = 160

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: !typeSize.isAccessibilitySize && availableWidth >= minimumWidth * 2 + 18 ? 2 : 1), spacing: 18) {
            tile {
                VStack(alignment: .leading, spacing: 6) {
                    Text(date.formatted(style.weekday(.wide))).font(.headline)
                    Text(date.formatted(style.day())).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text(date.formatted(style.month(.wide).year())).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gregorian-date-card")
            }
            if !weather.failed || weather.reading?.isCurrent(at: .now) == true {
                tile {
                    weatherContent
                } decoration: {
                    if let reading = weather.reading, reading.isCurrent(at: .now), model.location != nil {
                        WeatherCardScene(condition: reading.weatherCondition, sun: sun, moon: moon)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: Calendar(identifier: .gregorian), timeZone: model.zone)
    }

    private func tile(@ViewBuilder content: () -> some View, @ViewBuilder decoration: () -> some View = { EmptyView() }) -> some View {
        InfoCardLayout(square: !typeSize.isAccessibilitySize) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background { decoration() }
        .background {
            if skyBackground {
                SkyCardSurface().clipShape(.rect(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24).fill(.background)
            }
        }
        .clipShape(.rect(cornerRadius: 24))
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.location != nil {
                if weather.reading?.isCurrent(at: .now) != true {
                    weatherSkeleton
                } else if let reading = weather.reading {
                    Color.clear.frame(height: 58).accessibilityHidden(true)
                    Text(reading.temperature(feelsLike: model.preferences.showFeelsLikeTemperature),
                         format: .measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("weather-temperature")
                        .accessibilityValue(reading.condition)
                    WeatherAttributionLink(legalPageURL: reading.attribution?.legalPageURL,
                                           size: CGSize(width: 86, height: 16))
                }
            } else {
                Label("Weather", systemImage: "cloud.sun").font(.headline)
                NavigationLink("Choose a location") { LocationPicker() }.font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weather-card")
    }

    private var weatherSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Circle().frame(width: 28, height: 28)
            RoundedRectangle(cornerRadius: 8).frame(width: 96, height: 36)
            RoundedRectangle(cornerRadius: 4).frame(width: 86, height: 12)
        }
        .foregroundStyle(.quaternary)
        .accessibilityHidden(true)
    }
}
