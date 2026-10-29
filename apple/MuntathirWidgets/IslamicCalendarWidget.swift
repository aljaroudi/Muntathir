import SwiftUI
import AppIntents
import WeatherKit
import WidgetKit

struct IslamicDateEntry: TimelineEntry {
    let date: Date
    var settings = WidgetCalendarSettings()
    var location: SavedLocation?
    var weather: WeatherReading?

    var currentWeather: WeatherReading? {
        weather.flatMap { $0.isCurrent(at: date) ? $0 : nil }
    }

    var weatherTimeline: Timeline<IslamicDateEntry> {
        let dates = settings.timelineDates(from: date)
            + [900.0, 1800, 3600].map { date.addingTimeInterval($0) }
        let entries = Set(dates).sorted().map {
            IslamicDateEntry(date: $0, settings: settings, location: location, weather: weather)
        }
        return Timeline(entries: entries, policy: .after(date.addingTimeInterval(1800)))
    }
}

struct IslamicDateProvider: TimelineProvider {
    func placeholder(in _: Context) -> IslamicDateEntry {
        Self.preview()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (IslamicDateEntry) -> Void) {
        completion(context.isPreview ? Self.preview() : IslamicDateEntry(date: .now, settings: .read()))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<IslamicDateEntry>) -> Void) {
        let settings = WidgetCalendarSettings.read()
        let entries = settings.timelineDates(from: .now).map { IslamicDateEntry(date: $0, settings: settings) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func preview(condition: WeatherCondition = .clear) -> IslamicDateEntry {
        let date = Date.now
        return IslamicDateEntry(date: date, settings: WidgetCalendarSettings(timeZoneID: "Asia/Riyadh"),
                                location: WidgetPreviewData.entry.settings?.location,
                                weather: WeatherReading(temperature: .init(value: 24, unit: .celsius),
                                                        apparentTemperature: .init(value: 26, unit: .celsius),
                                                        condition: condition.description, weatherCondition: condition,
                                                        date: date, attribution: nil))
    }
}

struct IslamicDateWidgetView: View {
    let entry: IslamicDateEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        let engine = entry.settings.engine
        let day = engine.resolve(entry.date)
        let month = monthName(day.month, engine: engine)
        Group {
            if family == .accessoryInline {
                Text("\(day.day, format: .number) \(month)")
            } else if family == .systemSmall {
                calendarCard
            } else {
                ViewThatFits {
                    VStack(spacing: 2) {
                        Text(day.day, format: .number)
                            .font(.title2.weight(.semibold))
                            .widgetAccentable()
                        Text(month)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Text("\(day.day.formatted(.number.locale(locale))) \(month)")
                        .font(.headline).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        Text(day.day, format: .number)
                            .font(.headline).widgetAccentable()
                        Text(month)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.number.locale(locale))) \(month)")
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var calendarCard: CalendarCard {
        CalendarCard(date: entry.date, settings: entry.settings)
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

struct IslamicCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IslamicCalendar", provider: IslamicDateProvider()) {
            IslamicDateWidgetView(entry: $0)
        }
        .configurationDisplayName("Islamic calendar")
        .description("Hijri and Gregorian dates.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeatherDateWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WeatherDate", intent: WeatherDateConfiguration.self,
                               provider: WeatherDateProvider()) { entry in
            WeatherDateCard(date: entry.reading.date, settings: entry.reading.settings,
                            weather: entry.reading.currentWeather, usesHijriDate: entry.calendar == .hijri)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Weather")
        .description("Current weather with the weekday and date.")
        .supportedFamilies([.systemSmall])
    }
}

enum WeatherDateCalendar: String, AppEnum {
    case hijri, gregorian
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Calendar" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.hijri: "Hijri", .gregorian: "Gregorian"]
    }
}

struct WeatherDateConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Weather" }
    @Parameter(title: "Calendar", default: .hijri) var calendar: WeatherDateCalendar
}

struct WeatherDateEntry: TimelineEntry {
    let reading: IslamicDateEntry
    var calendar: WeatherDateCalendar = .hijri
    var date: Date { reading.date }
}

struct WeatherDateProvider: AppIntentTimelineProvider {
    static func weatherEntry() async -> IslamicDateEntry {
        let location = WidgetPrayerStore.read()?.location
        var entry = IslamicDateEntry(date: .now, settings: .read(), location: location)
        if let location {
            entry.weather = await SharedWeatherStore.refresh(for: location)
        }
        return entry
    }

    func placeholder(in context: Context) -> WeatherDateEntry {
        WeatherDateEntry(reading: IslamicDateProvider.preview())
    }

    func snapshot(for configuration: WeatherDateConfiguration, in context: Context) async -> WeatherDateEntry {
        let reading = context.isPreview ? IslamicDateProvider.preview()
            : await Self.weatherEntry()
        return WeatherDateEntry(reading: reading, calendar: configuration.calendar)
    }

    func timeline(for configuration: WeatherDateConfiguration, in context: Context) async -> Timeline<WeatherDateEntry> {
        let reading = await Self.weatherEntry()
        let timeline = reading.weatherTimeline
        let entries = timeline.entries.map {
            WeatherDateEntry(reading: $0, calendar: configuration.calendar)
        }
        return Timeline(entries: entries, policy: timeline.policy)
    }
}

#Preview("Weather", as: .systemSmall) {
    WeatherDateWidget()
} timeline: { WeatherDateEntry(reading: IslamicDateProvider.preview()) }

#Preview("Calendar · Small", as: .systemSmall) {
    IslamicCalendarWidget()
} timeline: { IslamicDateProvider.preview() }

#Preview("Calendar · Inline", as: .accessoryInline) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

#Preview("Calendar · Circular", as: .accessoryCircular) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

#Preview("Calendar · Rectangular", as: .accessoryRectangular) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

private struct IslamicCalendarWidgetTextSizePreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular], id: \.self) { family in
            ForEach([DynamicTypeSize.large, .xxxLarge, .accessibility3], id: \.self) { size in
                ForEach(["en_US", "ar_SA"], id: \.self) { language in
                    IslamicDateWidgetView(entry: IslamicDateProvider.preview())
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.locale, Locale(identifier: language))
                        .environment(\.layoutDirection, language == "ar_SA" ? .rightToLeft : .leftToRight)
                        .previewContext(WidgetPreviewContext(family: family))
                        .previewDisplayName("\(language) · \(size)")
                }
            }
        }
    }
}

struct CalendarWeatherProvider: TimelineProvider {
    func placeholder(in _: Context) -> IslamicDateEntry { IslamicDateProvider.preview() }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (IslamicDateEntry) -> Void) {
        if context.isPreview {
            completion(IslamicDateProvider.preview())
        } else {
            Task { completion(await WeatherDateProvider.weatherEntry()) }
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<IslamicDateEntry>) -> Void) {
        Task {
            let reading = await WeatherDateProvider.weatherEntry()
            completion(reading.weatherTimeline)
        }
    }
}

struct CalendarWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalendarWeather", provider: CalendarWeatherProvider()) { entry in
            CalendarWeatherCard(date: entry.date, settings: entry.settings, weather: entry.currentWeather)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                    LinearGradient(colors: [.cyan.opacity(0.08), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
        }
        .configurationDisplayName("Calendar & Weather")
        .description("Hijri and Gregorian dates with current weather.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Calendar & Weather", as: .systemSmall) {
    CalendarWeatherWidget()
} timeline: { IslamicDateProvider.preview(condition: .rain) }
