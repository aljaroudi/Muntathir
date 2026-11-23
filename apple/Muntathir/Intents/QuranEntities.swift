import AppIntents
import CoreSpotlight
import Foundation

// Entity ids are saved in shortcuts and Spotlight; never change their format.

struct SurahEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Surah", numericFormat: "\(placeholder: .int) surahs")
    static let defaultQuery = SurahQuery()

    /// The chapter number, 1 through 114.
    let id: Int
    @Property(title: "Name") var name: String
    @Property(title: "Arabic Name") var arabicName: String
    /// The name in the app's language: Arabic in Arabic, transliterated otherwise.
    private let title: String

    init(_ surah: QuranSurah) {
        id = surah.id
        title = surah.id.formatted() + ". " + surah.title(locale: .current)
        name = surah.transliteration
        arabicName = surah.arabic
    }

    var displayRepresentation: DisplayRepresentation {
        // Synonyms let Siri match the name however it's said, in either script.
        DisplayRepresentation(title: "\(title)", subtitle: "\(arabicName)", image: .init(systemName: "book.closed"),
                              synonyms: ["\(name)", "\(arabicName)", "\(id.formatted())"])
    }
}

struct SurahQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [SurahEntity] {
        let surahs = Dictionary(uniqueKeysWithValues: QuranSurah.bundled.map { ($0.id, $0) })
        return identifiers.compactMap { surahs[$0] }.map(SurahEntity.init)
    }

    func entities(matching string: String) async throws -> [SurahEntity] {
        QuranSurah.bundled.filter { $0.matches(string) }.map(SurahEntity.init)
    }

    func suggestedEntities() async throws -> [SurahEntity] {
        QuranSurah.bundled.map(SurahEntity.init)
    }
}

@available(iOS 27, macOS 27, *)
extension SurahQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [Int], indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(suggestedEntities())
    }
}

struct AyahEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ayah", numericFormat: "\(placeholder: .int) ayahs")
    static let defaultQuery = AyahQuery()

    /// "surah:verse", the same form as `Ayah.id`.
    let id: String
    @Property(title: "Surah") var surah: Int
    @Property(title: "Verse") var verse: Int
    @Property(title: "Text") var text: String
    @Property(title: "Translation") var translation: String?

    init(_ ayah: Ayah) {
        id = ayah.id
        surah = ayah.surah
        verse = ayah.number
        text = ayah.text
        translation = ayah.selectedTranslationText
    }

    /// The surah's name and the verse reference, such as "Al-Baqarah 2:255".
    var reference: String {
        let name = QuranSurah.bundled.first { $0.id == surah }?.title(locale: .current) ?? ""
        return name + " " + id
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(reference)", subtitle: "\(translation ?? text)", image: .init(systemName: "text.quote"))
    }
}

struct AyahQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AyahEntity] {
        let database = QuranDatabase(bundle: .main)
        return try identifiers.compactMap { id in
            guard let reference = try? QuranSearchText.reference(id) else { return nil }
            return try database.verse(surah: reference.surah, number: reference.verse).map(AyahEntity.init)
        }
    }

    /// A reference such as "2:255" opens that verse; anything else searches the text.
    func entities(matching string: String) async throws -> [AyahEntity] {
        if let reference = try? QuranSearchText.reference(string) {
            return try await entities(for: ["\(reference.surah):\(reference.verse)"])
        }
        return try await QuranReader.shared.search(string, translationID: QuranTranslationPreferences.selected?.id, limit: 20)
            .map(AyahEntity.init)
    }

    func suggestedEntities() async throws -> [AyahEntity] {
        []
    }
}
