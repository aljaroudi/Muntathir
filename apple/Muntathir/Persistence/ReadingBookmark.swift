import Foundation

struct ReadingBookmark: Codable, Equatable, Identifiable, Sendable {
    let source: String
    let isHadith: Bool
    var excerpt: String
    var reference: String
    var createdAt = Date.now
    var modifiedAt = Date.now

    var id: String {
        (isHadith ? "hadith:" : "quran:") + source
    }
}
