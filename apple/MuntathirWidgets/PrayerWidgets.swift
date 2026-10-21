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

struct PrayerWidgetView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
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
                    countdown
                    Divider()
                    Group {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(
                                    .flexible(),
                                    alignment: .leading
                                ),
                                count: 3
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
                        }.font(.caption2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            if let location = entry.settings?.location, renderingMode == .fullColor,
               let sun = SolarPosition.calculate(at: entry.date, latitude: location.latitude, longitude: location.longitude)
            {
                PrayerSkyBackground(sun: sun)
            } else {
                Color(.systemBackground)
            }
        }
    }

    @ViewBuilder private var countdown: some View {
        if let next = entry.next {
            HStack {
                Label(next.name.title, systemImage: next.name.symbol).fontWeight(.semibold)
                Spacer(minLength: 4)
                time(next.date)
                Text(PrayerCountdownFormat(target: next.date, locale: locale).format(entry.date))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).widgetAccentable()
            }.font(.caption).accessibilityElement(children: .combine)
        } else {
            Text("Prayer times unavailable for this location and date.").font(.caption)
        }
    }

    private var compactContent: some View {
        let upcoming = entry.settings?.upcomingPrayers(after: entry.date) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if let first = upcoming.first {
                VStack(alignment: .leading, spacing: 1) {
                    Label(first.name.title, systemImage: first.name.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                    time(first.date).font(.title2.weight(.semibold)).widgetAccentable()
                    Text(PrayerCountdownFormat(target: first.date, locale: locale).format(entry.date))
                        .font(.caption).monospacedDigit().lineLimit(1)
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

struct CombinedPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PrayerCountdownAndTimes",
            provider: PrayerProvider()
        ) {
            PrayerWidgetView(entry: $0)
        }
        .configurationDisplayName("Prayer times")
        .description(
            "The next prayer countdown alongside your prayer schedule."
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct MuntathirWidgetBundle: WidgetBundle {
    var body: some Widget {
        CombinedPrayerWidget()
        IslamicCalendarWidget()
        NextPrayerWidget()
        PrayerCountdownWidget()
        DailyAyahWidget()
    }
}

enum WidgetPreviewData {
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
                hiddenPrayers: []
            )
        )
    }
}

#Preview("Combined · Small", as: .systemSmall) {
    CombinedPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Combined · Medium", as: .systemMedium) {
    CombinedPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Location needed", as: .systemSmall) {
    CombinedPrayerWidget()
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

private struct PrayerSkyBackground: View {
    let sun: SolarPosition
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(x: 12, y: 8, width: max(0, geometry.size.width - 24), height: max(0, geometry.size.height * 0.55))
            ZStack {
                Color(.systemBackground)
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                if let progress = sun.daylightProgress {
                    Path { path in
                        for step in 0 ... 60 {
                            let point = SolarArcLayout.point(progress: Double(step) / 60, in: bounds)
                            if step == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                    }.stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    Circle().fill(.yellow.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .blur(radius: 2)
                        .position(SolarArcLayout.point(progress: progress, in: bounds))
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let tint: Color = sun.elevation < -6 ? .indigo : sun.elevation < 10 ? .orange : .cyan
        let base = Color(.systemBackground)
        return [tint.opacity(colorScheme == .dark ? 0.25 : 0.14), base]
    }
}
