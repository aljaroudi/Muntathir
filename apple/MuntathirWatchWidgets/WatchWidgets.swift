import SwiftUI
import WidgetKit

struct WatchEntry: TimelineEntry {
    let date: Date
    let settings: WatchSettings?
    let next: PrayerMoment?

    init(date: Date, settings: WatchSettings?) {
        self.date = date
        self.settings = settings
        next = settings?.prayers.nextPrayer(after: date)
    }

    static var preview: Self {
        .init(date: .now, settings: .init(prayers: .init(location: .init(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"), method: .tehran, hiddenPrayers: [.asr, .isha]), calendar: .init(timeZoneID: "Asia/Riyadh")))
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in _: Context) -> WatchEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? .preview : .init(date: .now, settings: .read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let settings = WatchSettings.read()
        let prayerDates = settings?.prayers.timelineDates(from: now) ?? [now]
        let calendarDates = (settings?.calendar ?? WidgetCalendarSettings()).timelineDates(from: now)
        let dates = Set(prayerDates + calendarDates).sorted()
        completion(Timeline(entries: dates.map { WatchEntry(date: $0, settings: settings) }, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

struct WatchPrayerWidgetView: View {
    let entry: WatchEntry
    var countdown = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let next = entry.next {
                let time = next.date.formatted(.dateTime.hour().minute().locale(locale).inZone(entry.settings?.prayers.location?.timeZone ?? .current))
                let remaining = String(PrayerCountdownFormat(target: next.date, locale: locale).format(entry.date).characters)
                if family == .accessoryInline {
                    Text("\(next.name.title) \(countdown ? remaining : time)")
                } else if family == .accessoryCorner {
                    Image(systemName: next.name.symbol)
                        .widgetLabel { Text("\(next.name.title) \(countdown ? remaining : time)") }
                } else {
                    ViewThatFits {
                        prayerContent(next, time: time, remaining: remaining, details: true, symbol: true).fixedSize()
                        prayerContent(next, time: time, remaining: remaining, details: false, symbol: true).fixedSize()
                        prayerContent(next, time: time, remaining: remaining, details: false, symbol: false).fixedSize()
                        Text(countdown ? remaining : time).font(.headline).monospacedDigit()
                            .lineLimit(2).minimumScaleFactor(0.7)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: family == .accessoryRectangular ? .leading : .center)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Text(next.name.title)) \(countdown ? remaining + " " + time : time)"))
                }
            } else {
                if family == .accessoryInline {
                    Text("Open Muntathir on iPhone")
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "iphone")
                        Text("Open Muntathir on iPhone").font(.caption2).multilineTextAlignment(.center)
                    }
                }
            }
        }.containerBackground(.background, for: .widget)
    }

    private func prayerContent(_ next: PrayerMoment, time: String, remaining: String, details: Bool, symbol: Bool) -> some View {
        VStack(alignment: family == .accessoryRectangular ? .leading : .center, spacing: 3) {
            HStack(spacing: 4) {
                if symbol { Image(systemName: next.name.symbol).accessibilityHidden(true) }
                Text(next.name.title)
            }
            .font(.caption).widgetAccentable()
            Text(countdown ? remaining : time).font(.headline).monospacedDigit()
            if details, countdown, family == .accessoryRectangular {
                Text(time).font(.caption)
            }
        }
    }

}

struct WatchDateWidgetView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        let engine = (entry.settings?.calendar ?? WidgetCalendarSettings()).engine
        let day = engine.resolve(entry.date)
        let month = monthName(day.month, engine: engine)
        Group {
            if family == .accessoryInline {
                Text("\(day.day, format: .number) \(month)")
            } else if family == .accessoryCorner {
                Text(day.day, format: .number).widgetLabel { Text(month) }
            } else {
                ViewThatFits {
                    VStack(spacing: 2) {
                        Text(day.day, format: .number).font(.title2.weight(.semibold)).widgetAccentable()
                        Text(month).font(.caption).multilineTextAlignment(.center)
                    }.fixedSize(horizontal: false, vertical: true)
                    Text("\(day.day.formatted(.number.locale(locale))) \(month)")
                        .font(.headline).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(day.day, format: .number)
                        .font(.title2.weight(.semibold)).lineLimit(1).widgetAccentable()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.number.locale(locale))) \(month)")
            }
        }.containerBackground(.background, for: .widget)
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

struct WatchDateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchIslamicDate", provider: WatchProvider()) { WatchDateWidgetView(entry: $0) }
            .configurationDisplayName("Islamic calendar")
            .description("The Hijri day and month.")
            .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct WatchNextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNextPrayer", provider: WatchProvider()) { WatchPrayerWidgetView(entry: $0) }
            .configurationDisplayName("Upcoming prayer")
            .description("Prayer times for your saved location.")
            .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct WatchCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchPrayerCountdown", provider: WatchProvider()) { WatchPrayerWidgetView(entry: $0, countdown: true) }
            .configurationDisplayName("Prayer countdown")
            .description("Next prayer time and a live countdown.")
            .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchDateWidget()
        WatchNextPrayerWidget()
        WatchCountdownWidget()
    }
}

#Preview("Date", as: .accessoryCircular) { WatchDateWidget() } timeline: { WatchEntry.preview }
#Preview("Next prayer", as: .accessoryRectangular) { WatchNextPrayerWidget() } timeline: { WatchEntry.preview }
#Preview("Countdown", as: .accessoryRectangular) { WatchCountdownWidget() } timeline: { WatchEntry.preview }
#Preview("Corner", as: .accessoryCorner) { WatchCountdownWidget() } timeline: { WatchEntry.preview }
#Preview("Inline", as: .accessoryInline) { WatchDateWidget() } timeline: { WatchEntry.preview }

private struct WatchWidgetsTextSizePreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner], id: \.self) { family in
            ForEach([DynamicTypeSize.large, .xxxLarge, .accessibility3], id: \.self) { size in
                ForEach(["en_US", "ar_SA"], id: \.self) { language in
                    WatchPrayerWidgetView(entry: .preview, countdown: true)
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
