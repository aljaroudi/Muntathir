import SwiftUI

struct HadithBookmarkButton: View {
    let narration: Hadith
    @Environment(\.quranUserStore) private var store
    @State private var failed = false

    private var key: String {
        narration.source?.key ?? ""
    }

    private var saved: Bool {
        store?.hadithState(for: key).isFavorite ?? false
    }

    var body: some View {
        Button {
            do {
                guard let store, !key.isEmpty else { throw QuranUserStoreError.unavailable }
                try store.setHadithFavorite(!saved, for: key)
            } catch { failed = true }
        } label: {
            Label(saved ? "Remove bookmark" : "Bookmark", systemImage: saved ? "bookmark.fill" : "bookmark")
        }
        .disabled(key.isEmpty)
        .accessibilityIdentifier("hadith-bookmark")
        .accessibilityValue(saved ? String(localized: "Saved") : String(localized: "Not saved"))
        .alert("Unable to save", isPresented: $failed) { Button("OK", role: .cancel) {} }
        message: { Text("Your change was not saved. Please try again.") }
    }
}
