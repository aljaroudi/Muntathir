import SwiftUI
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
}

struct IslamicDateProvider: TimelineProvider {
    func placeholder(in _: Context) -> IslamicDateEntry {
        Self.preview()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (IslamicDateEntry) -> Void) {
        if context.isPreview {
            completion(Self.preview())
        } else {
            let includeWeather = context.family == .systemSmall
            Task { await completion(entry(includeWeather: includeWeather)) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<IslamicDateEntry>) -> Void) {
        let includeWeather = context.family == .systemSmall
        Task {
            let entry = await entry(includeWeather: includeWeather)
            var dates = entry.settings.timelineDates(from: entry.date)
            if includeWeather {
                // Recompute the sky while waiting for WidgetKit's next permitted refresh.
                dates += [900.0, 1800, 3600].map { entry.date.addingTimeInterval($0) }
            }
            completion(Timeline(entries: Set(dates).sorted().map { date in
                IslamicDateEntry(date: date, settings: entry.settings, location: entry.location,
                                 weather: entry.weather)
            }, policy: includeWeather ? .after(entry.date.addingTimeInterval(1800)) : .atEnd))
        }
    }

    private func entry(includeWeather: Bool) async -> IslamicDateEntry {
        let location = WidgetPrayerStore.read()?.location
        var entry = IslamicDateEntry(date: .now, settings: .read(), location: location)
        if includeWeather, let location {
            entry.weather = await SharedWeatherStore.refresh(for: location)
        }
        return entry
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
    @Environment(\.widgetRenderingMode) private var renderingMode

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
                VStack(spacing: 0) {
                    Text(day.day, format: .number)
                        .font(.title2.weight(.semibold))
                        .widgetAccentable()
                    Text(month)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(family == .accessoryCircular ? 2 : 1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.number.locale(locale))) \(month)")
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                calendarCard.surface
            } else {
                Color(.systemBackground)
            }
        }
    }

    private var calendarCard: CalendarWeatherCard {
        CalendarWeatherCard(date: entry.date, settings: entry.settings, location: entry.location,
                            weather: entry.currentWeather, fullColor: renderingMode == .fullColor)
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
        .description("Hijri and Gregorian dates with current weather.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

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

#Preview("Calendar · Rain", as: .systemSmall) {
    IslamicCalendarWidget()
} timeline: { IslamicDateProvider.preview(condition: .rain) }

#Preview("Calendar · No weather", as: .systemSmall) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }
