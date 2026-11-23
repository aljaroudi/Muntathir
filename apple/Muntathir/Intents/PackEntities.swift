import AppIntents
import Foundation

// Hadith row ids change when a pack updates, so these entities are keyed by `HadithSource.key` instead.

struct HadithEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hadith", numericFormat: "\(placeholder: .int) hadith")
    static let defaultQuery = HadithQuery()

    let id: String
    @Property(title: "Book") var book: String
    @Property(title: "Text") var text: String
    private let number: Int?

    init?(_ hadith: Hadith) {
        guard let source = hadith.source else { return nil }
        id = source.key
        number = hadith.displayNumber
        book = hadith.chapter.bookTitle(locale: .current)
        text = Self.text(arabic: hadith.arabic, english: hadith.english)
    }

    /// Arabic for Arabic readers; English when the pack has it otherwise.
    static func text(arabic: String, english: String) -> String {
        let text = Locale.current.language.languageCode?.identifier == "ar" || english.isEmpty ? arabic : english
        return String(text.prefix(400))
    }

    var displayRepresentation: DisplayRepresentation {
        let title = number.map { book + " " + $0.formatted() } ?? book
        return DisplayRepresentation(title: "\(title)", subtitle: "\(text)", image: .init(systemName: "text.book.closed"))
    }
}

struct HadithQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [HadithEntity] {
        let reader = try await PackAccess.hadith()
        var entities: [HadithEntity] = []
        for key in identifiers {
            guard let source = HadithSource(key: key), let id = try await reader.resolve(source),
                  var narration = try? await reader.detail(id: id).narration else { continue }
            narration.source = source
            if let entity = HadithEntity(narration) {
                entities.append(entity)
            }
        }
        return entities
    }

    func entities(matching string: String) async throws -> [HadithEntity] {
        let reader = try await PackAccess.hadith()
        return try await reader.page(HadithRequest(query: string)).rows.prefix(20).compactMap(HadithEntity.init)
    }

    func suggestedEntities() async throws -> [HadithEntity] {
        []
    }
}

struct SupplicationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Supplication", numericFormat: "\(placeholder: .int) supplications")
    static let defaultQuery = SupplicationQuery()

    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Text") var text: String

    init?(_ supplication: Hadith) {
        guard let source = supplication.source else { return nil }
        id = source.key
        title = supplication.chapter.chapterTitle(locale: .current)
        text = supplication.translation?.text ?? String(supplication.arabic.prefix(400))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(text)", image: .init(systemName: "hands.sparkles"))
    }
}

struct SupplicationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SupplicationEntity] {
        let reader = try await PackAccess.supplications()
        let sources = identifiers.compactMap(HadithSource.init(key:))
        let locators = sources.map { "\($0.book):\($0.chapterFile):\($0.number)" }
        let rows = try await reader.supplications(locators: locators)
        // Locators omit the source id; keep each row's identity as the id it was asked for.
        let requested = Dictionary(zip(locators, sources), uniquingKeysWith: { first, _ in first })
        return rows.compactMap { row in
            var row = row
            if let source = row.source, let original = requested["\(source.book):\(source.chapterFile):\(source.number)"] {
                row.source = original
            }
            return SupplicationEntity(row)
        }
    }

    func entities(matching string: String) async throws -> [SupplicationEntity] {
        let reader = try await PackAccess.supplications()
        return try await reader.supplications(query: string).prefix(20).compactMap(SupplicationEntity.init)
    }

    func suggestedEntities() async throws -> [SupplicationEntity] {
        []
    }
}

struct RulingEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ruling", numericFormat: "\(placeholder: .int) rulings")
    static let defaultQuery = RulingQuery()

    /// `Rulings.ID.key`.
    let id: String
    @Property(title: "Question") var question: String
    @Property(title: "Answer") var answer: String

    init(_ ruling: Rulings) {
        id = ruling.id.key
        question = ruling.question
        answer = String(ruling.answer.prefix(600))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(question)", subtitle: "\(answer)", image: .init(systemName: "text.page"))
    }
}

struct RulingQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RulingEntity] {
        let reader = try await PackAccess.rulings()
        var entities: [RulingEntity] = []
        for key in identifiers {
            if let id = Rulings.ID(key: key), let ruling = try await reader.question(id) {
                entities.append(RulingEntity(ruling))
            }
        }
        return entities
    }

    /// Searches the authority chosen in the Rulings screen, in the app's language when the authority has it.
    func entities(matching string: String) async throws -> [RulingEntity] {
        let reader = try await PackAccess.rulings()
        let saved = UserDefaults.standard.string(forKey: "rulings.authority") ?? "sistani"
        let authorities = try await reader.authorities()
        guard let authority = authorities.first(where: { $0.id == saved }) ?? authorities.first else { return [] }
        let languages = try await reader.languages(authority: authority.id)
        guard let language = RulingsReader.preferredLanguage(saved: nil, locale: Locale.current.identifier, available: languages)
            ?? languages.first?.id else { return [] }
        return try await reader.questions(authority: authority.id, language: language, query: string).prefix(20).map(RulingEntity.init)
    }

    func suggestedEntities() async throws -> [RulingEntity] {
        []
    }
}
