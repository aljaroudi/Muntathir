import SwiftUI

struct QuranSavedVersesView: View {
    enum Kind { case favorites, notes }
    let kind: Kind
    let reader: QuranReader
    let surahs: [QuranSurah]
    @Environment(\.quranUserStore) private var store
    @State private var translationStore = QuranTranslationStore.shared
    @State private var verses: [Ayah] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    private struct Request: Equatable {
        let ids: [String]
        let retry: Int
        let translationRevision: Int
    }

    private var savedIDs: [String] {
        (store?.states.values.filter { kind == .favorites ? $0.isFavorite : !$0.note.isEmpty }.map(\.id) ?? []).sorted()
    }

    var body: some View {
        List {
            if store?.unavailable != false {
                ContentUnavailableView {
                    Label("Favorites and notes unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text("Your saved data could not be opened. Please try again.") }
                    actions: { Button("Try again") { store?.reopen() } }
            } else if loading {
                ProgressView("Loading Quran…")
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                } actions: { Button("Try again") { retry += 1 } }
            } else if verses.isEmpty {
                if kind == .favorites {
                    ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Use a verse’s actions to save it here."))
                } else {
                    ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Use a verse’s actions to add a note."))
                }
            } else {
                ForEach(verses) { ayah in
                    VStack(alignment: .leading, spacing: 12) {
                        QuranVerseRow(ayah: ayah, translation: QuranTranslation.catalog.first { $0.id == translationStore.activeID }, preview: true)
                        if kind == .notes, let note = store?.state(for: ayah.id).note {
                            Text(note).lineLimit(3).foregroundStyle(.secondary)
                        }
                        if let surah = surahs.first(where: { $0.id == ayah.surah }) {
                            NavigationLink {
                                QuranChapterView(surah: surah, initialVerse: ayah.number, reader: reader)
                            } label: { Label("Read verse", systemImage: "book") }
                                .accessibilityIdentifier("saved-verse-\(ayah.id)")
                        }
                    }
                }
            }
        }
        .navigationTitle(kind == .favorites ? Text("Favorites") : Text("Notes"))
        .task(id: Request(ids: savedIDs, retry: retry, translationRevision: translationStore.revision)) { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            let loaded = try await reader.verses(references: savedIDs)
            try Task.checkCancellation()
            verses = loaded
            loading = false
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            loading = false
            failed = true
        }
    }
}
