import Foundation

struct EventReference: Codable, Hashable, Sendable {
    let book: String
    let author: String?
    let edition: String?
    let volume: String?
    let page: String?
    var description: String { [book, author, edition, volume, page].compactMap { $0 }.joined(separator: " · ") }
}
struct IslamicEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let month: Int
    let day: Int
    let titleEN: String
    let titleAR: String
    let convention: String?
    let references: [EventReference]
    func title(arabic: Bool) -> String { arabic ? titleAR : titleEN }
}
struct Ayah: Identifiable, Sendable {
    let surah: Int
    let number: Int
    let text: String
    var id: String { "\(surah):\(number)" }
}
struct ContentLibrary: Sendable {
    let events: [IslamicEvent]
    let verses: [Ayah]
    init(bundle: Bundle = .main) {
        events = bundle.url(forResource: "events", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([IslamicEvent].self, from: $0) } ?? []
        let text = bundle.url(forResource: "quran-uthmani", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        verses = text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let surah = Int(fields[0]), let number = Int(fields[1]) else { return nil }
            return Ayah(surah: surah, number: number, text: String(fields[2]))
        }
    }
    func events(on day: ResolvedDay) -> [IslamicEvent] { events.filter { $0.month == day.month.month && $0.day == day.day } }
    func verse(on date: Date, timeZone: TimeZone) -> Ayah? {
        guard !verses.isEmpty else { return nil }
        let civil = CivilDate(date, in: timeZone)
        // FNV-1a gives a stable day selection across launches, devices and future clients.
        let key = "\(civil.year)-\(civil.month)-\(civil.day)"
        let hash = key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return verses[Int(hash % UInt64(verses.count))]
    }
}
