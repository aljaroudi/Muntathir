import Foundation

struct IslamicEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let month: Int
    let day: Int
    let title: [String: String]
    /// Optional Hijri year (AH). Negative values are before the Hijra.
    let year: Int?

    init(id: String, month: Int, day: Int, year: Int? = nil, title: [String: String]) {
        self.id = id
        self.month = month
        self.day = day
        self.title = title
        self.year = year
    }

    private func bundle(for locale: Locale) -> Bundle {
        let language = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [locale.identifier]).first ?? "en"
        return Bundle.main.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? .main
    }

    func title(locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        let key = language == "zh" ? "zh-\(locale.language.script?.identifier ?? "Hans")" : language
        return title[key] ?? title["en"] ?? id
    }

    /// Localized AH year for separate SwiftUI presentation; `nil` when the source has no year.
    func yearText(locale: Locale) -> String? {
        guard let year else { return nil }
        let format = bundle(for: locale).localizedString(forKey: "%lld AH", value: nil, table: nil)
        return String(format: format, locale: locale, year)
    }
}

struct Ayah: Identifiable, Sendable {
    let surah: Int
    let number: Int
    let text: String
    var translations: [String: String] = [:]

    var selectedTranslationText: String? {
        // Database reads include only the shared selected translation.
        translations.values.first
    }

    var id: String {
        "\(surah):\(number)"
    }
}

struct ContentLibrary: Sendable {
    let events: [IslamicEvent]
    let verses: [Ayah]

    init(bundle: Bundle = .main) {
        events = bundle.url(forResource: "events", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([IslamicEvent].self, from: $0) } ?? []
        let dailyIDs = bundle.url(forResource: "quran-daily-ids", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? []
        let records = QuranDatabase(bundle: bundle).verses(ids: Set(dailyIDs))
        verses = dailyIDs.count == 360 && dailyIDs.allSatisfy { records[$0] != nil }
            ? dailyIDs.compactMap { records[$0] } : []
    }

    func events(on day: ResolvedDay) -> [IslamicEvent] {
        events.filter { $0.month == day.month.month && $0.day == day.day }
    }

    func nextEventDate(onOrAfter date: Date, engine: CalendarEngine) -> Date? {
        let today = engine.gregorian.startOfDay(for: date)
        let month = engine.resolve(today).month
        return (0 ... 12).lazy.compactMap { offset -> Date? in
            let candidate = month.advanced(offset)
            return engine.days(in: candidate).first {
                $0 >= today && !events(on: engine.resolve($0)).isEmpty
            }
        }.first
    }

    static func verseDay(on date: Date, engine: CalendarEngine, prayerSettings: WidgetPrayerSettings? = nil) -> ResolvedDay {
        let sunset = prayerSettings?.sunset(on: date)
        return engine.resolve(sunset.map { date >= $0 } == true ? engine.addingDays(1, to: date) : date)
    }

    func verse(on date: Date, engine: CalendarEngine, prayerSettings: WidgetPrayerSettings? = nil) -> Ayah? {
        verse(on: Self.verseDay(on: date, engine: engine, prayerSettings: prayerSettings))
    }

    func verse(on day: ResolvedDay) -> Ayah? {
        let index = (day.month.month - 1) * 30 + day.day - 1
        return verses.indices.contains(index) ? verses[index] : nil
    }
}
