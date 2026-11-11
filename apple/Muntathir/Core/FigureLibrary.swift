import Foundation

struct Figure: Decodable, Identifiable, Sendable {
    enum NameKind: String, CaseIterable, Sendable {
        case personal = "name"
        case full = "full_name"
        case surname, kunya, laqab, nisba, nickname, title
    }

    struct Names: Decodable, Sendable {
        private struct NameKey: CodingKey {
            let stringValue: String
            var intValue: Int? {
                nil
            }

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue _: Int) {
                nil
            }
        }

        private let values: [String: [String]]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NameKey.self)
            var decoded: [String: [String]] = [:]
            for key in container.allKeys {
                let nameKey = key.stringValue == "fullName" ? "full_name" : key.stringValue
                if nameKey == "name" || nameKey == "full_name" {
                    decoded[nameKey] = try [container.decode(String.self, forKey: key)]
                } else {
                    decoded[key.stringValue] = try container.decode([String].self, forKey: key)
                }
            }
            values = decoded
        }

        subscript(kind: NameKind) -> [String] {
            values[kind.rawValue] ?? []
        }

        var aliases: [String] {
            values.values.flatMap(\.self)
        }
    }

    let id: String
    let verified: Bool?
    let displayNames: [String: String]
    let names: [String: Names]
    let birthDates: [FigureDate]
    let deathDates: [FigureDate]
    let notes: [String: String]?

    func title(_ locale: Locale) -> String {
        Self.localized(displayNames, locale) ?? id
    }

    func names(_ kind: NameKind, locale: Locale) -> [String] {
        Self.languageKeys(names, locale).lazy.map { names[$0]?[kind] ?? [] }
            .first { !$0.isEmpty } ?? []
    }

    static func localized<T>(_ values: [String: T], _ locale: Locale) -> T? {
        languageKeys(values, locale).lazy.compactMap { values[$0] }.first
    }

    private static func languageKeys(_ values: [String: some Any], _ locale: Locale) -> [String] {
        let exact = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let language = locale.language.languageCode?.identifier ?? "en"
        let script = locale.language.script.map { "\(language)-\($0.identifier)" }
        return [exact] + (script.map { [$0] } ?? []) + [language, "en", "ar"] + values.keys.sorted()
    }
}

struct FigureNotes: Decodable, Sendable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let legacy = try? container.decode(String.self) {
            values = ["en": legacy]
        } else {
            values = try container.decode([String: String].self)
        }
    }
}

enum FigureClaimStatus: String, Decodable, Sendable {
    case accepted, disputed, unreviewed
}

struct FigureCitation: Decodable, Sendable {
    let sourceId: String
    let locator: String
    let quote: String?
}

struct FigureDate: Decodable, Hashable, Sendable {
    enum CalendarKind: String, Decodable, Sendable { case gregorian, julian, hijri }
    enum Era: String, Decodable, Sendable { case ce = "CE", bce = "BCE", ah = "AH", bh = "BH" }
    enum Precision: String, Decodable, Sendable { case exact, approximate, range }

    struct Point: Decodable, Hashable, Sendable {
        let year: Int
        let month: Int?
        let day: Int?
    }

    let calendar: CalendarKind
    let era: Era
    let precision: Precision
    let start: Point
    let end: Point?
    let original: String
    let status: FigureClaimStatus
    let citations: [FigureCitation]
    let notes: FigureNotes?

    private enum CodingKeys: String, CodingKey {
        case calendar, era, precision, start, end, original, status, citations, notes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        calendar = try values.decode(CalendarKind.self, forKey: .calendar)
        era = try values.decode(Era.self, forKey: .era)
        precision = try values.decode(Precision.self, forKey: .precision)
        start = try values.decode(Point.self, forKey: .start)
        end = try values.decodeIfPresent(Point.self, forKey: .end)
        original = try values.decode(String.self, forKey: .original)
        status = try values.decode(FigureClaimStatus.self, forKey: .status)
        citations = try values.decodeIfPresent([FigureCitation].self, forKey: .citations) ?? []
        notes = try values.decodeIfPresent(FigureNotes.self, forKey: .notes)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.calendar == rhs.calendar && lhs.era == rhs.era && lhs.precision == rhs.precision
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.original == rhs.original && lhs.status == rhs.status
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(calendar)
        hasher.combine(era)
        hasher.combine(precision)
        hasher.combine(start)
        hasher.combine(end)
        hasher.combine(original)
        hasher.combine(status)
    }
}

struct FigureParentage: Decodable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable { case biological, adoptive, foster }

    let id: String
    let childId: String
    let fatherId: String?
    let motherId: String?
    let unionId: String?
    let kind: Kind
    let status: FigureClaimStatus
    let citations: [FigureCitation]
    let notes: FigureNotes?

    var parentIDs: [String] {
        [fatherId, motherId].compactMap(\.self)
    }

    var isDefault: Bool {
        kind == .biological && status == .accepted
    }

    func otherParent(of id: String) -> String? {
        fatherId == id ? motherId : fatherId
    }
}

struct FigureUnion: Decodable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable { case marriage, reportedPartnership = "reported-partnership" }
    let id: String
    let partnerIds: [String]
    let kind: Kind
    let status: FigureClaimStatus
    let citations: [FigureCitation]
    let notes: FigureNotes?
}

struct FigureLibrary: Sendable {
    enum Failure: Error, Equatable { case unsupportedVersion, invalidRelationships }
    enum SiblingDegree: String, CaseIterable, Sendable { case full, half, unknown }

    private struct Source: Decodable, Sendable {
        let id: String
        let title: String
        let author: String?
        let edition: String?
        let url: String?
        let notes: String?
    }

    private struct Dataset: Decodable {
        let schemaVersion: Int
        let people: [Figure]
        let parentages: [FigureParentage]
        let unions: [FigureUnion]
        let sources: [Source]
    }

    let people: [Figure]
    let byID: [String: Figure]
    let parents: [String: [FigureParentage]]
    let children: [String: [FigureParentage]]
    let partners: [String: [FigureUnion]]
    let events: [String: [IslamicEvent]]
    private let sources: [Source]
    private let searchTerms: [String: [String]]

    static let bundledEvents = Bundle.main.url(forResource: "events", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([IslamicEvent].self, from: $0) } ?? []

    init(data: Data, events: [IslamicEvent] = [], verifiedOnly: Bool = true) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dataset = try decoder.decode(Dataset.self, from: data)
        guard dataset.schemaVersion == 1 else { throw Failure.unsupportedVersion }
        let ids = Set(dataset.people.map(\.id))
        let unionIDs = Set(dataset.unions.map(\.id))
        guard ids.count == dataset.people.count, unionIDs.count == dataset.unions.count,
              Set(dataset.parentages.map(\.id)).count == dataset.parentages.count,
              dataset.parentages.allSatisfy({ ids.contains($0.childId) && !$0.parentIDs.isEmpty
                      && !$0.parentIDs.contains($0.childId) && $0.parentIDs.allSatisfy(ids.contains)
                      && ($0.unionId.map(unionIDs.contains) ?? true) }),
              dataset.unions.allSatisfy({ $0.partnerIds.count == 2 && Set($0.partnerIds).count == 2
                      && $0.partnerIds.allSatisfy(ids.contains) })
        else { throw Failure.invalidRelationships }
        people = dataset.people.filter { !verifiedOnly || $0.verified == true }
        let publishedIDs = Set(people.map(\.id))
        let unions = dataset.unions.filter { $0.partnerIds.allSatisfy(publishedIDs.contains) }
        let publishedUnionIDs = Set(unions.map(\.id))
        let parentages = dataset.parentages.filter {
            publishedIDs.contains($0.childId) && $0.parentIDs.allSatisfy(publishedIDs.contains)
                && ($0.unionId.map(publishedUnionIDs.contains) ?? true)
        }
        byID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        parents = Dictionary(grouping: parentages, by: \.childId)
        children = Dictionary(grouping: parentages.flatMap { claim in
            claim.parentIDs.map { ($0, claim) }
        }, by: \.0).mapValues { $0.map(\.1) }
        partners = Dictionary(grouping: unions.flatMap { union in
            union.partnerIds.map { ($0, union) }
        }, by: \.0).mapValues { $0.map(\.1) }
        self.events = Dictionary(grouping: events.sorted {
            ($0.month, $0.day, $0.id) < ($1.month, $1.day, $1.id)
        }.flatMap { event in
            event.figureIDs.filter(publishedIDs.contains).map { ($0, event) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let citations = people.flatMap { ($0.birthDates + $0.deathDates).flatMap(\.citations) }
            + parentages.flatMap(\.citations) + unions.flatMap(\.citations)
        let sourceIDs = Set(citations.map(\.sourceId))
        guard sourceIDs.isSubset(of: Set(dataset.sources.map(\.id))) else { throw Failure.invalidRelationships }
        sources = dataset.sources.filter { sourceIDs.contains($0.id) }
        searchTerms = people.reduce(into: [:]) { terms, figure in
            terms[figure.id] = Array(figure.displayNames.values) + figure.names.values.flatMap(\.aliases)
        }
    }

    func search(_ query: String, locale: Locale) -> [Figure] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { person in
            searchTerms[person.id, default: []].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }

    func siblings(of id: String, account: FigureParentage?) -> [SiblingDegree: [Figure]] {
        guard let account else { return [:] }
        let candidateIDs = Set(account.parentIDs.flatMap { parent in
            children[parent, default: []].filter(\.isDefault).map(\.childId)
        }).subtracting([id])
        var result: [SiblingDegree: [Figure]] = [:]
        for candidate in people where candidateIDs.contains(candidate.id) {
            let claims = parents[candidate.id, default: []].filter(\.isDefault)
            guard claims.count == 1, let other = claims.first else { continue }
            let shared = Set(account.parentIDs).intersection(other.parentIDs)
            guard !shared.isEmpty else { continue }
            let degree: SiblingDegree = shared.count == 2 ? .full
                : (account.parentIDs.count == 2 && other.parentIDs.count == 2 ? .half : .unknown)
            result[degree, default: []].append(candidate)
        }
        return result
    }

    func childGroups(of id: String, choices: [String: String] = [:]) -> [[FigureParentage]] {
        let claims = children[id, default: []].filter { claim in
            guard claim.isDefault else { return false }
            let accounts = parents[claim.childId, default: []].filter(\.isDefault)
            return accounts.count == 1 || choices[claim.childId] == claim.id
        }
        var groups: [[FigureParentage]] = []
        for claim in claims {
            if let index = groups.firstIndex(where: { $0.first?.otherParent(of: id) == claim.otherParent(of: id) }) {
                groups[index].append(claim)
            } else {
                groups.append([claim])
            }
        }
        return groups
    }
}

actor FigureStore {
    static let shared = FigureStore()
    private var library: Result<FigureLibrary, any Error>?

    func load() -> Result<FigureLibrary, any Error> {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               let fixture = ProcessInfo.processInfo.environment["UITEST_FIGURES"],
               let data = Data(base64Encoded: fixture)
            {
                return Result { try FigureLibrary(data: data, events: FigureLibrary.bundledEvents) }
            }
        #endif
        if let library {
            return library
        }
        let loaded = Result {
            guard let url = Bundle.main.url(forResource: "figures", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try FigureLibrary(data: Data(contentsOf: url), events: FigureLibrary.bundledEvents)
        }
        library = loaded
        return loaded
    }
}
