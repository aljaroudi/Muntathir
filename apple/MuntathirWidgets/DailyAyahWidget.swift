import SwiftUI
import WidgetKit

struct DailyAyahEntry: TimelineEntry {
    let date: Date
    let ayah: Ayah?
    var translation: QuranTranslation?
}

struct DailyAyahProvider: TimelineProvider {
    func placeholder(in _: Context) -> DailyAyahEntry {
        DailyAyahEntry(date: .now, ayah: .init(surah: 20, number: 25, text: "قَالَ رَبِّ ٱشْرَحْ لِى صَدْرِى"))
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyAyahEntry) -> Void) {
        let now = Date()
        let library = ContentLibrary()
        completion(context.isPreview ? placeholder(in: context) : entry(at: now, library: library, settings: .read(), prayerSettings: WidgetPrayerStore.read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<DailyAyahEntry>) -> Void) {
        let settings = WidgetCalendarSettings.read()
        let library = ContentLibrary()
        let prayerSettings = WidgetPrayerStore.read()
        let dates = prayerSettings?.dailyVerseTimelineDates(from: .now, engine: settings.engine) ?? settings.timelineDates(from: .now)
        let entries = dates.map { entry(at: $0, library: library, settings: settings, prayerSettings: prayerSettings) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, library: ContentLibrary, settings: WidgetCalendarSettings, prayerSettings: WidgetPrayerSettings?) -> DailyAyahEntry {
        DailyAyahEntry(date: date, ayah: library.verse(on: date, engine: settings.engine, prayerSettings: prayerSettings), translation: QuranTranslationPreferences.selected)
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
                ViewThatFits(in: .vertical) {
                    ayahContent(ayah, heading: !isAccessory, translation: !isAccessory, lines: 2)
                        .fixedSize(horizontal: false, vertical: true)
                    ayahContent(ayah, heading: false, translation: !isAccessory, lines: 2)
                        .fixedSize(horizontal: false, vertical: true)
                    ayahContent(ayah, heading: false, translation: false, lines: 2)
                        .fixedSize(horizontal: false, vertical: true)
                    ayahContent(ayah, heading: false, translation: false, lines: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text([ayah.text, isAccessory ? nil : entry.translation.flatMap { ayah.translations[$0.id] }, ayah.id].compactMap(\.self).joined(separator: " ")))
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

    private func ayahContent(_ ayah: Ayah, heading: Bool, translation: Bool, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: isAccessory ? 2 : 6) {
            if heading {
                Label("Daily ayah", systemImage: "book.closed")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Text(ayah.text)
                .font(.custom("KFGQPCHAFSUthmanicScript-Regula", size: isAccessory ? 17 : 28, relativeTo: isAccessory ? .body : .title2))
                .lineSpacing(isAccessory ? 0 : 2)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .lineLimit(lines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            if translation, let selected = entry.translation, let text = ayah.translations[selected.id] {
                Text(text)
                    .font(.caption)
                    .environment(\.layoutDirection, Locale(identifier: selected.language).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isAccessory {
                Text(ayah.id)
                    .font(.caption.monospacedDigit()).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(1)
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

private struct DailyAyahWidgetTextSizePreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemMedium, .accessoryRectangular], id: \.self) { family in
            ForEach([DynamicTypeSize.large, .xxxLarge, .accessibility3], id: \.self) { size in
                ForEach(["en_US", "ar_SA"], id: \.self) { language in
                    DailyAyahWidgetView(entry: AyahWidgetPreview.long)
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
