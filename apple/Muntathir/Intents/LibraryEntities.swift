import AppIntents
import CoreSpotlight
import Foundation

struct FigureEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Figure", numericFormat: "\(placeholder: .int) figures")
    static let defaultQuery = FigureQuery()

    let id: String
    @Property(title: "Name") var name: String

    init(_ figure: Figure) {
        id = figure.id
        name = figure.title(.current)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "person"))
    }
}

struct FigureQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [FigureEntity] {
        let library = try await FigureStore.shared.load().get()
        return identifiers.compactMap { library.byID[$0] }.map(FigureEntity.init)
    }

    func entities(matching string: String) async throws -> [FigureEntity] {
        try await FigureStore.shared.load().get().search(string, locale: .current).map(FigureEntity.init)
    }

    func suggestedEntities() async throws -> [FigureEntity] {
        try await FigureStore.shared.load().get().people.map(FigureEntity.init)
    }
}

@available(iOS 27, macOS 27, *)
extension FigureQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [String], indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(suggestedEntities())
    }
}

struct IslamicEventEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Islamic Event", numericFormat: "\(placeholder: .int) Islamic events")
    static let defaultQuery = IslamicEventQuery()

    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Hijri Month") var month: Int
    @Property(title: "Hijri Day") var day: Int
    /// The people the event commemorates, for opening their profiles.
    let figureIDs: [String]
    private let year: String?

    init(_ event: IslamicEvent) {
        id = event.id
        figureIDs = event.figureIDs
        year = event.yearText(locale: .current)
        title = event.title(locale: .current)
        month = event.month
        day = event.day
    }

    var displayRepresentation: DisplayRepresentation {
        if let year {
            DisplayRepresentation(title: "\(title)", subtitle: "\(year)", image: .init(systemName: "sparkle"))
        } else {
            DisplayRepresentation(title: "\(title)", image: .init(systemName: "sparkle"))
        }
    }
}

struct IslamicEventQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [IslamicEventEntity] {
        let events = Dictionary(ContentLibrary().events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { events[$0] }.map(IslamicEventEntity.init)
    }

    func entities(matching string: String) async throws -> [IslamicEventEntity] {
        let terms = QuranSearchText.queryTerms(string)
        return ContentLibrary().events.filter { event in
            let title = QuranSearchText.normalize(event.title(locale: .current)).lowercased()
            return !terms.isEmpty && terms.allSatisfy { title.contains($0) }
        }.map(IslamicEventEntity.init)
    }

    func suggestedEntities() async throws -> [IslamicEventEntity] {
        ContentLibrary().events.map(IslamicEventEntity.init)
    }
}

@available(iOS 27, macOS 27, *)
extension IslamicEventQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [String], indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(suggestedEntities())
    }
}
