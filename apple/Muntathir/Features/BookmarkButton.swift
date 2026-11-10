import SwiftUI

struct BookmarkButton: View {
    let source: String
    let isHadith: Bool
    let excerpt: String
    let reference: String
    @Environment(\.quranUserStore) private var store
    @Binding var failed: Bool

    private var bookmark: ReadingBookmark? {
        store?.bookmark(for: source, isHadith: isHadith)
    }

    var body: some View {
        Button(bookmark == nil ? "Bookmark" : "Remove Bookmark", systemImage: bookmark == nil ? "bookmark" : "bookmark.fill") {
            do {
                guard let store else { throw QuranUserStoreError.unavailable }
                if let bookmark {
                    try store.delete(bookmark)
                } else {
                    try store.save(ReadingBookmark(source: source, isHadith: isHadith, excerpt: excerpt, reference: reference))
                }
            } catch { failed = true }
        }
        .disabled(source.isEmpty)
        .accessibilityIdentifier(isHadith ? "hadith-bookmark" : "verse-bookmark")
    }
}
