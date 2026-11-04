import Foundation
import SwiftData

@Model final class HighlightRecord {
    #Index<HighlightRecord>([\.highlightID])
    var recordID: String = UUID().uuidString
    var highlightID: String = ""
    var installationID: String = ""
    var payload: Data = Data()
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var isTombstone: Bool = false

    init(highlightID: String, installationID: String) {
        self.highlightID = highlightID
        self.installationID = installationID
    }
}

struct HighlightRange: Codable, Equatable, Sendable {
    let location: Int
    let length: Int
    let quote: String

    init?(_ range: NSRange, in text: String) {
        guard range.length > 0, let indices = Range(range, in: text) else { return nil }
        location = range.location
        length = range.length
        quote = String(text[indices])
    }

    func validated(in text: String) -> NSRange? {
        guard location >= 0, length > 0, location <= text.utf16.count,
              length <= text.utf16.count - location else { return nil }
        let range = NSRange(location: location, length: length)
        guard let indices = Range(range, in: text), String(text[indices]) == quote else { return nil }
        return range
    }
}

enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow, green, blue, pink, purple
}

struct ReadingHighlight: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var source: String
    var isHadith: Bool
    // nil denotes the entire item; other values identify Arabic or a translation edition.
    var block: String?
    var ranges: [HighlightRange] = []
    var excerpt: String
    var reference: String
    var color: HighlightColor = .yellow
    var note = ""
    var createdAt = Date.now
    var modifiedAt = Date.now

    func ranges(in text: String, block: String) -> [NSRange] {
        guard let selectedBlock = self.block else { return [NSRange(location: 0, length: text.utf16.count)] }
        guard selectedBlock == block else { return [] }
        let validated = ranges.compactMap { $0.validated(in: text) }
        return validated.count == ranges.count ? validated : []
    }

    func isAvailable(in blocks: [String: String]) -> Bool {
        guard let block else { return true }
        guard let text = blocks[block], !ranges.isEmpty else { return false }
        return ranges.allSatisfy { $0.validated(in: text) != nil }
    }
}

struct HighlightSnapshot: Equatable, Sendable {
    let recordID: String
    let highlightID: String
    let payload: Data
    let modifiedAt: Date
    let isTombstone: Bool

    @MainActor init(_ row: HighlightRecord) {
        recordID = row.recordID
        highlightID = row.highlightID
        payload = row.payload
        modifiedAt = row.modifiedAt
        isTombstone = row.isTombstone
    }

    static func winners(_ rows: [Self]) -> [String: Self] {
        var result: [String: Self] = [:]
        for row in rows {
            if let old = result[row.highlightID],
               old.modifiedAt > row.modifiedAt || (old.modifiedAt == row.modifiedAt && old.recordID > row.recordID)
            {
                continue
            }
            result[row.highlightID] = row
        }
        return result
    }
}
