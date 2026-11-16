import Foundation

struct ReadingBookmark: Codable, Equatable, Identifiable, Sendable {
    let source: String
    let isHadith: Bool
    var excerpt: String
    var reference: String
    var ruling: Rulings.ID? = nil
    enum Kind { case quran, hadith, ruling }
    var kind: Kind {
        ruling != nil ? .ruling : (isHadith ? .hadith : .quran)
    }

    var createdAt = Date.now
    var modifiedAt = Date.now

    var id: String {
        if let ruling {
            // Length prefixes keep source identifiers unambiguous even when they contain punctuation.
            return "ruling:" + [ruling.authority, ruling.language, ruling.siteID].map { "\($0.utf8.count):\($0)" }.joined()
        }
        return (isHadith ? "hadith:" : "quran:") + source
    }
}

extension ReadingBookmark {
    private enum CodingKeys: String, CodingKey {
        case source, isHadith, excerpt, reference, ruling, createdAt, modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        ruling = try values.decodeIfPresent(Rulings.ID.self, forKey: .ruling)
        isHadith = ruling == nil ? try values.decode(Bool.self, forKey: .isHadith) : false
        excerpt = try values.decode(String.self, forKey: .excerpt)
        reference = try values.decode(String.self, forKey: .reference)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        // Older clients require isHadith; omit it for rulings so they cannot treat them as Quran bookmarks.
        if ruling == nil {
            try values.encode(isHadith, forKey: .isHadith)
        }
        try values.encodeIfPresent(ruling, forKey: .ruling)
        try values.encode(excerpt, forKey: .excerpt)
        try values.encode(reference, forKey: .reference)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(modifiedAt, forKey: .modifiedAt)
    }
}
