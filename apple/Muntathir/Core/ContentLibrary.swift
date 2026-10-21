import Foundation

struct EventReference: Codable, Hashable, Sendable {
    let book: String
    let author: String?
    let edition: String?
    let volume: String?
    let page: String?
    var description: String {
        [book, author, edition, volume, page].compactMap(\.self).joined(separator: " · ")
    }
}

struct IslamicEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let month: Int
    let day: Int
    let titles: [String: String]
    let convention: String?
    let references: [EventReference]
    func title(locale: Locale) -> String {
        func normalizedTag(_ identifier: String) -> String {
            let components = Locale.Components(identifier: identifier).languageComponents
            return [components.languageCode?.identifier, components.script?.identifier, components.region?.identifier]
                .compactMap(\.self).joined(separator: "-").lowercased()
        }

        let language = locale.language.languageCode?.identifier
        let script = locale.language.script?.identifier
        let languageWithScript = language.flatMap { language in
            script.map { "\(language)-\($0)" }
        }
        let region = Locale.Components(identifier: locale.identifier).languageComponents.region
        let fullLanguageTag = languageWithScript.flatMap { languageWithScript in
            region.map { "\(languageWithScript)-\($0.identifier)" }
        }
        let candidates = [locale.identifier, fullLanguageTag, languageWithScript, language, "en"]
            .compactMap(\.self)
        let keys = titles.keys.sorted()
        var visited: Set<String> = []
        for candidate in candidates {
            let normalized = normalizedTag(candidate)
            guard visited.insert(normalized).inserted else { continue }
            for key in keys where normalizedTag(key) == normalized {
                if let title = titles[key], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return title
                }
            }
        }
        return id
    }
}

struct Ayah: Identifiable, Sendable {
    let surah: Int
    let number: Int
    let text: String
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
        let text = bundle.url(forResource: "quran-daily", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        verses = text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let surah = Int(fields[0]), let number = Int(fields[1]) else { return nil }
            return Ayah(surah: surah, number: number, text: String(fields[2]))
        }
    }

    func events(on day: ResolvedDay) -> [IslamicEvent] {
        events.filter { $0.month == day.month.month && $0.day == day.day }
    }

    func verse(on date: Date, timeZone: TimeZone) -> Ayah? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard !verses.isEmpty, let day = calendar.ordinality(of: .day, in: .era, for: date) else { return nil }
        return verses[(day - 1) % verses.count]
    }
}
