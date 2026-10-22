import SwiftUI
import WidgetKit

struct DailyAyahEntry: TimelineEntry {
    let date: Date
    let ayah: Ayah?
}

struct DailyAyahProvider: TimelineProvider {
    func placeholder(in _: Context) -> DailyAyahEntry {
        DailyAyahEntry(date: .now, ayah: .init(surah: 20, number: 25, text: "قَالَ رَبِّ ٱشْرَحْ لِى صَدْرِى"))
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyAyahEntry) -> Void) {
        let now = Date()
        let library = ContentLibrary()
        completion(context.isPreview ? placeholder(in: context) : entry(at: now, library: library, settings: .read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<DailyAyahEntry>) -> Void) {
        let settings = WidgetCalendarSettings.read()
        let library = ContentLibrary()
        let entries = settings.timelineDates(from: .now).map { entry(at: $0, library: library, settings: settings) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, library: ContentLibrary, settings: WidgetCalendarSettings) -> DailyAyahEntry {
        DailyAyahEntry(date: date, ayah: library.verse(on: date, engine: settings.engine))
    }
}

struct DailyAyahWidgetView: View {
    let entry: DailyAyahEntry
    @Environment(\.widgetFamily) private var family
    private var isAccessory: Bool {
        family == .accessoryRectangular
    }

    var body: some View {
        Group {
            if let ayah = entry.ayah {
                VStack(alignment: .leading, spacing: isAccessory ? 2 : 8) {
                    if !isAccessory {
                        Label("Daily ayah", systemImage: "book.closed")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(ayah.text)
                        .font(.custom("KFGQPCHAFSUthmanicScript-Regula", size: isAccessory ? 17 : 28, relativeTo: isAccessory ? .body : .title2))
                        .lineSpacing(isAccessory ? 0 : 2)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineLimit(2)
                        .minimumScaleFactor(isAccessory ? 0.8 : 0.7)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    if !isAccessory, let english = ayah.translations["en.qarai"] {
                        Text(english)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .lineLimit(3)
                    }
                    if !isAccessory {
                        Text(ayah.id)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text([ayah.text, isAccessory ? nil : ayah.translations["en.qarai"], ayah.id].compactMap(\.self).joined(separator: " ")))
            } else {
                Text("Verse unavailable").font(.caption)
            }
        }
        .containerBackground(for: .widget) {
            if isAccessory {
                Color.clear
            } else {
                AyahBackground()
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                    }
            }
        }
    }
}

struct DailyAyahWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyAyah", provider: DailyAyahProvider()) {
            DailyAyahWidgetView(entry: $0)
        }
        .configurationDisplayName("Daily ayah")
        .description("Today's verse from the Quran.")
        .supportedFamilies([.accessoryRectangular, .systemMedium])
    }
}

private enum AyahWidgetPreview {
    static let short = DailyAyahEntry(date: .now, ayah: .init(surah: 20, number: 25, text: "قَالَ رَبِّ ٱشْرَحْ لِى صَدْرِى"))
    static let long = DailyAyahEntry(date: .now, ayah: ContentLibrary().verses.max { $0.text.count < $1.text.count })
}

#Preview("Ayah · Lock Screen", as: .accessoryRectangular) {
    DailyAyahWidget()
} timeline: { AyahWidgetPreview.short; AyahWidgetPreview.long }

#Preview("Ayah · Medium", as: .systemMedium) {
    DailyAyahWidget()
} timeline: { AyahWidgetPreview.short; AyahWidgetPreview.long }
