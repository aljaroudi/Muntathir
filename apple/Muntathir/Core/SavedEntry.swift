import Foundation

struct SavedEntry: Identifiable {
    let id: String
    let source: String
    let isHadith: Bool
    let reference: String
    let excerpt: String
    let note: String
    let createdAt: Date
    let modifiedAt: Date
    let highlight: ReadingHighlight?
    let bookmark: ReadingBookmark?

    init(_ highlight: ReadingHighlight) {
        id = "highlight:" + highlight.id
        source = highlight.source
        isHadith = highlight.isHadith
        reference = highlight.reference
        excerpt = highlight.excerpt
        note = highlight.note
        createdAt = highlight.createdAt
        modifiedAt = highlight.modifiedAt
        self.highlight = highlight
        bookmark = nil
    }

    init(_ bookmark: ReadingBookmark) {
        id = "bookmark:" + bookmark.id
        source = bookmark.source
        isHadith = bookmark.isHadith
        reference = bookmark.reference
        excerpt = bookmark.excerpt
        note = ""
        createdAt = bookmark.createdAt
        modifiedAt = bookmark.modifiedAt
        highlight = nil
        self.bookmark = bookmark
    }

    func title(locale: Locale) -> String {
        isHadith || locale.language.languageCode?.identifier != "ar"
            ? reference : QuranReference.display(source, locale: locale)
    }

    func matches(_ query: String, locale: Locale) -> Bool {
        let terms = QuranSearchText.terms(query).map {
            $0.folding(options: .diacriticInsensitive, locale: locale)
        }
        guard !terms.isEmpty else { return true }
        let text = QuranSearchText.normalize([isHadith ? "" : source, reference, title(locale: locale), excerpt, note].joined(separator: " "))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        return terms.allSatisfy { text.contains($0) }
    }

    static func sections(_ entries: [Self], byDate: Bool, query: String, calendar: Calendar, locale: Locale) -> [SavedEntrySection] {
        let filtered = entries.filter { $0.matches(query, locale: locale) }
        let groups = Dictionary(grouping: filtered) { entry in
            byDate ? "date:\(calendar.startOfDay(for: entry.createdAt).timeIntervalSince1970)"
                : (entry.isHadith ? "hadith:" : "quran:") + entry.source
        }
        return groups.map { key, values in
            let sorted = values.sorted {
                let lhs = byDate ? $0.createdAt : $0.modifiedAt
                let rhs = byDate ? $1.createdAt : $1.modifiedAt
                return lhs == rhs ? $0.id > $1.id : lhs > rhs
            }
            return SavedEntrySection(id: key, date: byDate ? calendar.startOfDay(for: sorted[0].createdAt) : nil, entries: sorted)
        }.sorted {
            let lhs = $0.date ?? $0.entries[0].modifiedAt
            let rhs = $1.date ?? $1.entries[0].modifiedAt
            return lhs == rhs ? $0.id > $1.id : lhs > rhs
        }
    }
}
