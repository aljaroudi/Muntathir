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
            } else {
                compactContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            if let location = entry.settings?.location, renderingMode == .fullColor,
               let sun = SolarPosition.calculate(at: entry.date, latitude: location.latitude, longitude: location.longitude)
            {
                PrayerSkyBackground(sun: sun)
            } else {
                #if os(macOS)
                    Color(nsColor: .windowBackgroundColor)
                #else
                    Color(.systemBackground)
                #endif
            }
        }
    }

    private var compactContent: some View {
        let upcoming = entry.settings?.upcomingPrayers(after: entry.date) ?? []
        return ViewThatFits(in: .vertical) {
            prayerContent(upcoming, rows: 2, countdown: true, symbols: true).fixedSize(horizontal: false, vertical: true)
            prayerContent(upcoming, rows: 1, countdown: true, symbols: true).fixedSize(horizontal: false, vertical: true)
            prayerContent(upcoming, rows: 0, countdown: true, symbols: true).fixedSize(horizontal: false, vertical: true)
            prayerContent(upcoming, rows: 0, countdown: false, symbols: true).fixedSize(horizontal: false, vertical: true)
            prayerContent(upcoming, rows: 0, countdown: false, symbols: false)
        }
    }

    private func prayerContent(_ upcoming: [PrayerMoment], rows: Int, countdown: Bool, symbols: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = upcoming.first {
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        if symbols {
                            Label(first.name.title, systemImage: first.name.symbol)
                                .fixedSize()
                        }
                        Text(first.name.title)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline.weight(.semibold))
                    time(first.date)
                        .font(symbols ? .title2.weight(.semibold) : .body.weight(.semibold))
                        .minimumScaleFactor(symbols ? 1 : 0.7)
                        .widgetAccentable()
                    if countdown {
                        Text(PrayerCountdownFormat(target: first.date, locale: locale).format(entry.date))
                            .font(.caption).monospacedDigit().lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(Text(first.name.title)) \(Text(first.date, format: .dateTime.hour().minute().locale(locale).inZone(entry.zone))) \(Text(PrayerCountdownFormat(target: first.date, locale: locale).format(entry.date)))"))
                ForEach(Array(upcoming.dropFirst().prefix(rows))) { prayer in
                    ViewThatFits(in: .horizontal) {
                        prayerRow(prayer, symbols: true)
                        prayerRow(prayer, symbols: false)
                        prayerRow(prayer, symbols: false, wraps: true)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Text(prayer.name.title)) \(Text(prayer.date, format: .dateTime.hour().minute().locale(locale).inZone(entry.zone)))"))
                }
            }
        }
    }

    private func prayerRow(_ prayer: PrayerMoment, symbols: Bool, wraps: Bool = false) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if symbols {
                    Image(systemName: prayer.name.symbol).accessibilityHidden(true)
                }
                Text(prayer.name.title)
                    .lineLimit(wraps ? nil : 1)
            }
            .fixedSize(horizontal: !wraps, vertical: true)
            Spacer(minLength: 0)
            time(prayer.date).fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(locale).inZone(entry.zone)))
            .monospacedDigit().lineLimit(1)
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
        .supportedFamilies([.systemSmall])
    }
}

@main struct MuntathirWidgetBundle: WidgetBundle {
    var body: some Widget {
        CombinedPrayerWidget()
        IslamicCalendarWidget()
        WeatherDateWidget()
        CalendarWeatherWidget()
        #if os(iOS)
            NextPrayerWidget()
            PrayerCountdownWidget()
        #endif
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

#Preview("Location needed", as: .systemSmall) {
    CombinedPrayerWidget()
} timeline: { PrayerEntry(date: .now, settings: nil) }

private struct PrayerSkyBackground: View {
    let sun: SolarPosition
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let tint: Color = sun.elevation < -6 ? .indigo : sun.elevation < 10 ? .orange : .cyan
        #if os(macOS)
            let base = Color(nsColor: .windowBackgroundColor)
        #else
            let base = Color(.systemBackground)
        #endif
        return [tint.opacity(colorScheme == .dark ? 0.25 : 0.14), base]
    }
}

private struct PrayerWidgetsTextSizePreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemSmall], id: \.self) { family in
            ForEach([DynamicTypeSize.large, .xxxLarge, .accessibility3], id: \.self) { size in
                ForEach(["en_US", "ar_SA"], id: \.self) { language in
                    PrayerWidgetView(entry: WidgetPreviewData.entry)
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
