import SwiftUI
import WidgetKit

struct LockScreenPrayerView: View {
    let entry: PrayerEntry
    let showsCountdown: Bool
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let next = entry.next {
                if family == .accessoryInline {
                    Text("\(Text(next.name.title)) \(value(for: next))")
                } else {
                    VStack(alignment: family == .accessoryCircular ? .center : .leading, spacing: 2) {
                        Text(next.name.title).font(.headline)
                        value(for: next)
                            .font(family == .accessoryCircular ? .caption : .title3)
                            .monospacedDigit()
                            .widgetAccentable()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: family == .accessoryCircular ? .center : .leading)
                }
            } else if entry.settings?.location == nil {
                Text("Set location in app")
                    .font(.caption).multilineTextAlignment(.center)
            } else {
                Text("Prayer times unavailable")
                    .font(.caption).multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .containerBackground(.background, for: .widget)
    }

    private func value(for prayer: PrayerMoment) -> Text {
        if showsCountdown {
            Text(PrayerCountdownFormat(target: prayer.date, locale: locale).format(entry.date))
        } else {
            Text(prayer.date, format: .dateTime.hour().minute().locale(locale).inZone(entry.zone))
        }
    }
}

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: PrayerProvider()) {
            LockScreenPrayerView(entry: $0, showsCountdown: false)
        }
        .configurationDisplayName("Next prayer")
        .description("The time of your next prayer.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct PrayerCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerCountdown", provider: PrayerProvider()) {
            LockScreenPrayerView(entry: $0, showsCountdown: true)
        }
        .configurationDisplayName("Prayer countdown")
        .description("Hours and minutes until your next prayer.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview("Next prayer · Inline", as: .accessoryInline) {
    NextPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Next prayer · Circular", as: .accessoryCircular) {
    NextPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Next prayer · Rectangular", as: .accessoryRectangular) {
    NextPrayerWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Countdown · Inline", as: .accessoryInline) {
    PrayerCountdownWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Countdown · Circular", as: .accessoryCircular) {
    PrayerCountdownWidget()
} timeline: { WidgetPreviewData.entry }

#Preview("Countdown · Rectangular", as: .accessoryRectangular) {
    PrayerCountdownWidget()
} timeline: { WidgetPreviewData.entry }
