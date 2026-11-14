import SwiftUI

struct BookmarkButton: View {
    let source: String
    let isHadith: Bool
    let excerpt: String
    let reference: String
    var ruling: Rulings.ID?
    @Environment(\.quranUserStore) private var store
    @Binding var failed: Bool

    private var bookmark: ReadingBookmark? {
        store?.bookmark(for: source, isHadith: isHadith, ruling: ruling)
    }

    var body: some View {
        Button(bookmark == nil ? "Bookmark" : "Remove Bookmark", systemImage: bookmark == nil ? "bookmark" : "bookmark.fill") {
            do {
                guard let store else { throw QuranUserStoreError.unavailable }
                if let bookmark {
                    try store.delete(bookmark)
                } else {
                    try store.save(ReadingBookmark(source: source, isHadith: isHadith, excerpt: excerpt, reference: reference, ruling: ruling))
                }
                AppTip.complete(.reading)
                AppTip.complete(.bookmarks)
            } catch { failed = true }
        }
        .disabled(source.isEmpty)
        .accessibilityIdentifier(ruling != nil ? "ruling-bookmark" : isHadith ? "hadith-bookmark" : "verse-bookmark")
    }
}
