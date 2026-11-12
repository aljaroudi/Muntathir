import Foundation
import SwiftData

@Model final class BookmarkRecord {
    #Index<BookmarkRecord>([\.bookmarkID])
    var recordID: String = UUID().uuidString
    var bookmarkID: String = ""
    var installationID: String = ""
    var payload: Data = Data()
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var isTombstone: Bool = false

    init(bookmarkID: String, installationID: String) {
        self.bookmarkID = bookmarkID
        self.installationID = installationID
    }
}
