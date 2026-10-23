import Foundation

struct IslamicEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let month: Int
    let day: Int

    func title(locale: Locale) -> String {
        let language = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [locale.identifier]).first ?? "en"
        let bundle = Bundle.main.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? .main
        return bundle.localizedString(forKey: "event.\(id)", value: nil, table: nil)
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
    private let datedSchedule: DailyVerseSchedule?
    private let hasDatedSchedule: Bool
    private let versesByID: [Int: Ayah]

    init(bundle: Bundle = .main) {
        events = bundle.url(forResource: "events", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([IslamicEvent].self, from: $0) } ?? []
        let scheduleURL = bundle.url(forResource: "quran-daily", withExtension: "json")
        hasDatedSchedule = scheduleURL != nil
        let schedule = scheduleURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(DailyVerseSchedule.self, from: $0) }
        let dailyIDs = bundle.url(forResource: "quran-daily-ids", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? []
        let ids = Set(dailyIDs + (schedule?.entries.map(\.verseID) ?? []))
        let records = QuranDatabase(bundle: bundle).verses(ids: ids)
        versesByID = records
        verses = dailyIDs.compactMap { records[$0] }
        datedSchedule = schedule.flatMap { candidate in
            candidate.entries.allSatisfy { records[$0.verseID] != nil } ? candidate : nil
        }
    }

    func events(on day: ResolvedDay) -> [IslamicEvent] {
        events.filter { $0.month == day.month.month && $0.day == day.day }
    }

    func verse(on date: Date, engine: CalendarEngine) -> Ayah? {
        if hasDatedSchedule {
            return datedSchedule?.verseID(on: engine.resolve(date)).flatMap { versesByID[$0] }
        }
        // Keep the existing rotation until a complete dated schedule is bundled.
        let calendar = engine.gregorian
        // Era ordinals need a normalized date to stay fixed until local midnight.
        guard !verses.isEmpty, let day = calendar.ordinality(of: .day, in: .era, for: calendar.startOfDay(for: date)) else { return nil }
        return verses[(day - 1) % verses.count]
    }
}

/// A dated schedule is accepted as a whole; every reference must resolve in the Quran database.
struct DailyVerseSchedule: Decodable, Sendable {
    struct Entry: Codable, Sendable {
        let hijriMonth: Int
        let hijriDay: Int
        let verseID: Int
    }

    let entries: [Entry]

    init(entries: [Entry]) throws {
        var dates = Set<Int>()
        guard entries.count == 360 else { throw ValidationError.invalidSchedule }
        for entry in entries {
            guard (1 ... 12).contains(entry.hijriMonth), (1 ... 30).contains(entry.hijriDay), entry.verseID > 0,
                  dates.insert((entry.hijriMonth - 1) * 30 + entry.hijriDay).inserted
            else { throw ValidationError.invalidSchedule }
        }
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entries: container.decode([Entry].self, forKey: .entries))
    }

    func verseID(on day: ResolvedDay) -> Int? {
        entries.first { $0.hijriMonth == day.month.month && $0.hijriDay == day.day }?.verseID
    }

    private enum CodingKeys: String, CodingKey { case entries }
    enum ValidationError: Error { case invalidSchedule }
}
