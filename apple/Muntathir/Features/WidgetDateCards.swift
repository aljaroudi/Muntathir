import SwiftUI

/// Shared with the widget so its compact layout can be rendered and checked in app tests.
struct CalendarCard: View {
    let date: Date
    let settings: WidgetCalendarSettings
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .largeTitle) private var daySize = 36
    @ScaledMetric(relativeTo: .title) private var compactDaySize = 28

    var body: some View {
        let day = settings.engine.resolve(date)
        let dateLabel = "\(day.day.formatted(.number.locale(locale))) \(monthName(day.month, engine: settings.engine))"
        return Group {
            if dynamicTypeSize <= .large {
                // Normal text sizes always retain the selected design's complete content.
                ViewThatFits(in: .vertical) {
                    content(secondaryDates: true)
                        .fixedSize(horizontal: false, vertical: true)
                    content(secondaryDates: true, compact: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                adaptiveContent(dateLabel: dateLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func adaptiveContent(dateLabel: String) -> some View {
        let day = settings.engine.resolve(date)
        return ViewThatFits {
            content(secondaryDates: true).fixedSize(horizontal: false, vertical: true)
            content(secondaryDates: true, compact: true).fixedSize(horizontal: false, vertical: true)
            content(secondaryDates: false).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.day, format: .number).font(.title2.weight(.semibold)).fixedSize()
                Text(monthName(day.month, engine: settings.engine)).font(.headline)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(day.day, format: .number)
                .font(.title2.weight(.semibold)).lineLimit(1)
                .accessibilityLabel(dateLabel)
        }
    }

    private func content(secondaryDates: Bool, compact: Bool = false) -> some View {
        let engine = settings.engine
        let day = engine.resolve(date)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.day, format: .number)
                    .font(.system(size: compact ? compactDaySize : daySize, weight: .medium, design: .rounded)).fixedSize()
                if secondaryDates {
                    Text(date.formatted(Date.FormatStyle(locale: locale, calendar: engine.gregorian, timeZone: settings.zone).weekday(.abbreviated)))
                        .font((compact ? Font.caption2 : .caption).weight(.medium))
                }
            }
            Text(monthName(day.month, engine: engine)).font(compact ? .subheadline.weight(.semibold) : .headline).fixedSize()
            if secondaryDates {
                Text(gregorianDate).font(.caption2).fixedSize()
            }
        }
        .lineLimit(1)
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

struct WeatherDateCard: View {
    let date: Date
    let settings: WidgetCalendarSettings
    let weather: WeatherReading?
    var usesHijriDate = true
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    weekday
                    shortDate
                }.fixedSize()
                shortDate.fixedSize()
            }
            Spacer(minLength: 0)
            if let weather {
                WidgetTemperature(weather: weather, feelsLike: settings.showFeelsLikeTemperature ?? false)
                    .font(.largeTitle.weight(.medium))
                Text(weather.condition)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WeatherAttributionLink(legalPageURL: weather.attribution?.legalPageURL,
                                       size: CGSize(width: 46, height: 8))
            } else {
                Text("Weather unavailable")
                    .font(.headline)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var weekday: some View {
        Text(date, format: Date.FormatStyle(locale: locale, calendar: settings.engine.gregorian,
                                          timeZone: settings.zone).weekday(.abbreviated))
            .font(.subheadline.weight(.medium))
    }

    private var shortDate: some View {
        let engine = settings.engine
        let day = engine.resolve(date)
        let calendar = usesHijriDate ? engine.baseline : engine.gregorian
        // Format resolved Hijri components to retain the user's month corrections.
        let displayDate = usesHijriDate
            ? calendar.date(from: DateComponents(year: day.month.year, month: day.month.month, day: day.day)) ?? date
            : date
        // Islamic CLDR date styles expand months to names; use the locale's numeric ordering with Hijri values.
        var numericLocale = Locale.Components(identifier: locale.identifier)
        numericLocale.calendar = .gregorian
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = settings.zone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "Md", options: 0,
                                                       locale: Locale(components: numericLocale))
        return Text(verbatim: formatter.string(from: displayDate))
            .font(.subheadline)
    }
}

struct CalendarWeatherCard: View {
    let date: Date
    let settings: WidgetCalendarSettings
    let weather: WeatherReading?
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var daySize = 36
    @ScaledMetric(relativeTo: .title) private var compactDaySize = 28

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(secondaryDates: true)
                .fixedSize(horizontal: false, vertical: true)
            content(secondaryDates: true, compact: true)
                .fixedSize(horizontal: false, vertical: true)
            content(secondaryDates: false, compact: true)
                .fixedSize(horizontal: false, vertical: true)
            CalendarCard(date: date, settings: settings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func content(secondaryDates: Bool, compact: Bool = false) -> some View {
        let engine = settings.engine
        let day = engine.resolve(date)
        return VStack(alignment: .leading, spacing: 1) {
            if secondaryDates {
                Text(date.formatted(Date.FormatStyle(locale: locale, calendar: engine.gregorian,
                    timeZone: settings.zone).weekday(.abbreviated)))
                    .font((compact ? Font.caption2 : .caption).weight(.medium))
            }
            Text(day.day, format: .number)
                .font(.system(size: compact ? compactDaySize : daySize, weight: .medium, design: .rounded))
            Text(engine.baselineStart(day.month).formatted(Date.FormatStyle(locale: locale,
                calendar: engine.baseline, timeZone: settings.zone).month(.wide)))
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .fixedSize(horizontal: false, vertical: true)
            if secondaryDates {
                Text(date.formatted(Date.FormatStyle(locale: locale, calendar: engine.gregorian,
                    timeZone: settings.zone).month(.abbreviated).day()))
                    .font(.caption2)
            }
            if let weather {
                Divider().padding(.vertical, 3)
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    WidgetTemperature(weather: weather, feelsLike: settings.showFeelsLikeTemperature ?? false)
                        .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    WeatherAttributionLink(legalPageURL: weather.attribution?.legalPageURL,
                        size: CGSize(width: 46, height: 8))
                }
            }
        }
    }

    private var symbol: String {
        switch WeatherSceneStyle(weather?.weatherCondition) {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .fog: "cloud.fog.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .wind: "wind"
        }
    }
}

private struct WidgetTemperature: View {
    let weather: WeatherReading
    let feelsLike: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: weather.temperature(feelsLike: feelsLike).formatted(
            .measurement(width: .narrow, usage: .weather, hidesScaleName: true,
                         numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityValue(weather.condition)
    }
}
