import SwiftUI
import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let settings: WidgetPrayerSettings?
    var prayers: [PrayerMoment] {
        settings?.prayers(on: date) ?? []
    }

    var next: PrayerMoment? {
        settings?.nextPrayer(after: date)
    }

    var zone: TimeZone {
        settings?.location?.timeZone ?? .current
    }
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in _: Context) -> PrayerEntry {
        WidgetPreviewData.entry
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PrayerEntry) -> Void
    ) {
        completion(
            context.isPreview
                ? placeholder(in: context)
                : PrayerEntry(date: .now, settings: WidgetPrayerStore.read())
        )
    }

    func getTimeline(
        in _: Context,
        completion: @escaping (Timeline<PrayerEntry>) -> Void
    ) {
        let now = Date()
        let settings = WidgetPrayerStore.read()
        let dates = settings?.timelineDates(from: now) ?? [now]
        completion(
            Timeline(
                entries: dates.map {
                    PrayerEntry(date: $0, settings: settings)
                },
                policy: .after(now.addingTimeInterval(6 * 60 * 60))
            )
        )
    }
}

enum PrayerWidgetLayout { case countdown, times, combined }

struct PrayerWidgetView: View {
    let entry: PrayerEntry
    let layout: PrayerWidgetLayout
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if entry.settings?.location == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Prayer times", systemImage: "moon")
                    Text("Choose a location in Muntathir").font(.caption)
                }
            } else if entry.prayers.isEmpty {
                Text("Prayer times unavailable for this location and date.")
                    .font(.caption)
            } else if family == .systemSmall {
                compactContent
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if layout != .times {
                        countdown
                    }
                    if layout == .combined {
                        Divider()
                    }
                    if layout != .countdown {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(
                                    .flexible(),
                                    alignment: .leading
                                ),
                                count: 4
                            ),
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(entry.prayers) { prayer in
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(prayer.name.title, systemImage: prayer.name.symbol).foregroundStyle(
                                        .secondary
                                    ).lineLimit(1).minimumScaleFactor(0.8)
                                    time(prayer.date).fontWeight(.semibold)
                                }
                            }
                        }.font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder private var countdown: some View {
        if let next = entry.next {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(next.name.title, systemImage: next.name.symbol).fontWeight(.semibold)
                    Spacer(minLength: 4)
                    time(next.date)
                }.font(layout == .combined ? .caption : .headline)
                Text(PrayerCountdownFormat(target: next.date, locale: locale).format(entry.date))
                    .font(
                        layout == .combined ? .headline : .title2.weight(.semibold)
                    )
                    .monospacedDigit().minimumScaleFactor(0.7)
                    .widgetAccentable()
            }.accessibilityElement(children: .combine)
        } else {
            Text("Prayer times unavailable for this location and date.").font(.caption)
        }
    }

    private var compactContent: some View {
        let upcoming = (layout == .combined
            ? entry.settings?.upcomingPrayers(after: entry.date)
            : entry.settings?.upcomingTimes(after: entry.date)) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if layout == .countdown {
                countdown
            } else if let first = upcoming.first {
                VStack(alignment: .leading, spacing: 1) {
                    Label(first.name.title, systemImage: first.name.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                    time(first.date).font(.title2.weight(.semibold)).widgetAccentable()
                    if layout == .combined {
                        Text(PrayerCountdownFormat(target: first.date, locale: locale).format(entry.date))
                            .font(.caption).monospacedDigit().lineLimit(1)
                    }
                }.accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                ForEach(Array(upcoming.dropFirst().prefix(2))) { prayer in
                    HStack(spacing: 4) {
                        Label(prayer.name.title, systemImage: prayer.name.symbol).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        time(prayer.date)
                    }.font(.caption).accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour().minute().inZone(entry.zone)))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
    }
}

struct UpcomingPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingPrayer", provider: PrayerProvider()) {
            PrayerWidgetView(entry: $0, layout: .countdown)
        }
        .configurationDisplayName("Upcoming prayer")
        .description("Next prayer time and a live countdown.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PrayerTimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerTimes", provider: PrayerProvider()) {
            PrayerWidgetView(entry: $0, layout: .times)
        }
        .configurationDisplayName("Prayer times")
        .description("Prayer times for your saved location.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CombinedPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PrayerCountdownAndTimes",
            provider: PrayerProvider()
        ) {
            PrayerWidgetView(entry: $0, layout: .combined)
        }
        .configurationDisplayName("Countdown and prayer times")
        .description(
            "The next prayer countdown alongside your prayer schedule."
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct MuntathirWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingPrayerWidget()
        PrayerTimesWidget()
        CombinedPrayerWidget()
        IslamicCalendarWidget()
    }
}

private enum WidgetPreviewData {
    static var entry: PrayerEntry {
        PrayerEntry(
            date: .now,
            settings: .init(
                location: .init(
                    latitude: 21.4225,
                    longitude: 39.8262,
                    name: "Mecca",
                    countryCode: "SA",
                    timeZoneID: "Asia/Riyadh"
                ),
                method: .tehran,
                asrRule: .standard,
                hiddenPrayers: []
            )
        )
    }
}

#Preview("Upcoming · Small", as: .systemSmall) {
    UpcomingPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Upcoming · Medium", as: .systemMedium) {
    UpcomingPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Times · Small", as: .systemSmall) {
    PrayerTimesWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Times · Medium", as: .systemMedium) {
    PrayerTimesWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Combined · Small", as: .systemSmall) {
    CombinedPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Combined · Medium", as: .systemMedium) {
    CombinedPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Location needed", as: .systemSmall) {
    UpcomingPrayerWidget()
} timeline: { PrayerEntry(date: .now, settings: nil) }

struct IslamicDateEntry: TimelineEntry {
    let date: Date
    var settings = WidgetCalendarSettings()
}

struct IslamicDateProvider: TimelineProvider {
    func placeholder(in _: Context) -> IslamicDateEntry {
        IslamicDateEntry(date: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping (IslamicDateEntry) -> Void) {
        completion(IslamicDateEntry(date: .now, settings: .read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<IslamicDateEntry>) -> Void) {
        let settings = WidgetCalendarSettings.read()
        let dates = settings.timelineDates(from: .now)
        completion(Timeline(entries: dates.map { IslamicDateEntry(date: $0, settings: settings) },
                            policy: .atEnd))
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
            } else {
                VStack(spacing: family == .systemSmall ? 6 : 0) {
                    Text(day.day, format: .number)
                        .font(family == .systemSmall ? .system(size: 52, weight: .semibold, design: .rounded) : .title2.weight(.semibold))
                        .widgetAccentable()
                    Text(month)
                        .font(family == .systemSmall ? .headline : .caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(family == .accessoryCircular ? 2 : 1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.number.locale(locale))) \(month)")
            }
        }
        .containerBackground(.background, for: .widget)
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
        .description("The Hijri day and month.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview("Calendar · Small", as: .systemSmall) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

#Preview("Calendar · Inline", as: .accessoryInline) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

#Preview("Calendar · Circular", as: .accessoryCircular) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }

#Preview("Calendar · Rectangular", as: .accessoryRectangular) {
    IslamicCalendarWidget()
} timeline: { IslamicDateEntry(date: .now) }
