import SwiftUI

/// Shared with the widget so its compact layout can be rendered and checked in app tests.
struct CalendarWeatherCard: View {
    let date: Date
    let settings: WidgetCalendarSettings
    let location: SavedLocation?
    let weather: WeatherReading?
    var attributionLight: Data?
    var attributionDark: Data?
    var fullColor = true
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let engine = settings.engine
        let day = engine.resolve(date)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(date.formatted(Date.FormatStyle(locale: locale, calendar: engine.gregorian, timeZone: settings.zone).weekday(.abbreviated)))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let weather {
                    Text(weather.temperature(feelsLike: settings.showFeelsLikeTemperature ?? false),
                         format: .measurement(width: .narrow, usage: .weather, hidesScaleName: true,
                                              numberFormatStyle: .number.precision(.fractionLength(0))))
                        .font(.title2.weight(.semibold))
                        .accessibilityValue(weather.condition)
                } else {
                    Text(verbatim: "—").foregroundStyle(.secondary)
                        .accessibilityLabel("Weather unavailable")
                }
            }
            HStack(alignment: .center, spacing: 0) {
                Text(day.day, format: .number)
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                if let weather, let location, fullColor {
                    WeatherCardScene(condition: weather.weatherCondition,
                                     sun: SolarPosition.calculate(at: date, latitude: location.latitude, longitude: location.longitude),
                                     moon: MoonPosition.calculate(at: date, latitude: location.latitude, longitude: location.longitude),
                                     showsTint: false)
                        .frame(width: 100, height: 96)
                        .scaleEffect(0.65)
                        .frame(width: 65, height: 62)
                }
            }
            Text(monthName(day.month, engine: engine))
                .font(.headline)
            Spacer(minLength: 2)
            HStack(alignment: .bottom, spacing: 4) {
                Text(gregorianDate).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let attribution = weather?.attribution {
                    Link(destination: attribution.legalPageURL) {
                        if let data = colorScheme == .dark ? attributionDark : attributionLight,
                           let image = UIImage(data: data)
                        {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 58, height: 10)
                        } else {
                            Text("Apple Weather").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }.accessibilityLabel("Apple Weather attribution")
                }
            }
        }
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    var surface: some View {
        ZStack {
            Color(.systemBackground)
            if weather != nil, fullColor {
                LinearGradient(colors: [(isDaylight ? Color.cyan : .indigo).opacity(colorScheme == .dark ? 0.2 : 0.1), .clear],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
    }

    private var isDaylight: Bool {
        location.flatMap { SolarPosition.calculate(at: date, latitude: $0.latitude, longitude: $0.longitude) }?.daylightProgress != nil
    }

    private var gregorianDate: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = settings.zone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func monthName(_ month: HijriMonth, engine: CalendarEngine) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = engine.baseline
        formatter.timeZone = engine.timeZone
        formatter.dateFormat = "MMMM"
        return formatter.string(from: engine.baselineStart(month))
    }
}
