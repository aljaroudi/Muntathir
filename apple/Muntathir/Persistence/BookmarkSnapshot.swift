import Foundation

struct BookmarkSnapshot: Equatable, Sendable {
    let recordID: String
    let bookmarkID: String
    let payload: Data
    let modifiedAt: Date
    let isTombstone: Bool

    @MainActor init(_ row: BookmarkRecord) {
        recordID = row.recordID
        bookmarkID = row.bookmarkID
        payload = row.payload
        modifiedAt = row.modifiedAt
        isTombstone = row.isTombstone
    }

    static func winners(_ rows: [Self]) -> [String: Self] {
        var result: [String: Self] = [:]
        for row in rows {
            if let old = result[row.bookmarkID],
               old.modifiedAt > row.modifiedAt || (old.modifiedAt == row.modifiedAt && old.recordID > row.recordID)
            {
                continue
            }
            result[row.bookmarkID] = row
        }
        return result
    }
}
