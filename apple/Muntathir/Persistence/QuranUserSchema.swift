import Foundation
import SwiftData

/// Released schemas are immutable. Add a new VersionedSchema and migration stage for future changes.
enum QuranUserSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        .init(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Annotation.self]
    }

    @Model final class Annotation {
        #Index<Annotation>([\.verseID])

        var recordID: String = UUID().uuidString
        var verseID: String = ""
        var installationID: String = ""
        var isFavorite: Bool = false
        var favoriteModifiedAt: Date = Date(timeIntervalSince1970: 0)
        var note: String = ""
        var noteModifiedAt: Date = Date(timeIntervalSince1970: 0)

        init(verseID: String, installationID: String) {
            self.verseID = verseID
            self.installationID = installationID
        }
    }
}

enum QuranUserMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [QuranUserSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

typealias QuranAnnotation = QuranUserSchemaV1.Annotation

struct QuranAnnotationSnapshot: Equatable, Sendable {
    let recordID: String
    let verseID: String
    let isFavorite: Bool
    let favoriteModifiedAt: Date
    let note: String
    let noteModifiedAt: Date

    @MainActor init(_ annotation: QuranAnnotation) {
        recordID = annotation.recordID
        verseID = annotation.verseID
        isFavorite = annotation.isFavorite
        favoriteModifiedAt = annotation.favoriteModifiedAt
        note = annotation.note
        noteModifiedAt = annotation.noteModifiedAt
    }
}

struct QuranVerseState: Equatable, Sendable, Identifiable {
    let id: String
    var isFavorite = false
    var note = ""
    var favoriteModifiedAt = Date(timeIntervalSince1970: 0)
    var noteModifiedAt = Date(timeIntervalSince1970: 0)
    private var favoriteRecordID = ""
    private var noteRecordID = ""

    init(id: String) {
        self.id = id
    }

    static func resolve(_ rows: [QuranAnnotationSnapshot]) -> [String: QuranVerseState] {
        var result: [String: QuranVerseState] = [:]
        for row in rows {
            var state = result[row.verseID] ?? QuranVerseState(id: row.verseID)
            if row.favoriteModifiedAt > state.favoriteModifiedAt || (row.favoriteModifiedAt == state.favoriteModifiedAt && row.recordID > state.favoriteRecordID) {
                state.isFavorite = row.isFavorite
                state.favoriteModifiedAt = row.favoriteModifiedAt
                state.favoriteRecordID = row.recordID
            }
            if row.noteModifiedAt > state.noteModifiedAt || (row.noteModifiedAt == state.noteModifiedAt && row.recordID > state.noteRecordID) {
                state.note = row.note
                state.noteModifiedAt = row.noteModifiedAt
                state.noteRecordID = row.recordID
            }
            result[row.verseID] = state
        }
        return result
    }
}
