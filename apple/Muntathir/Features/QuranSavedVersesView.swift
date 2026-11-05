import SwiftUI

struct QuranSavedVersesView: View {
    let reader: QuranReader
    let surahs: [QuranSurah]
    @Environment(\.quranUserStore) private var store
    @State private var translationStore = QuranTranslationStore.shared
    @State private var verses: [Ayah] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var editing: ReadingHighlight?

    private struct Request: Equatable {
        let ids: [String]
        let retry: Int
        let translationRevision: Int
    }

    private var highlights: [ReadingHighlight] {
        store?.highlights.filter { !$0.isHadith } ?? []
    }

    private var savedIDs: [String] {
        Array(Set(highlights.map(\.source))).sorted()
    }

    var body: some View {
        List {
            if store?.unavailable != false {
                ContentUnavailableView {
                    Label("Highlights unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text("Your saved data could not be opened. Please try again.") }
                    actions: { Button("Try again") { store?.reopen() } }
            } else if loading {
                ProgressView("Loading Quran…")
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                } actions: { Button("Try again") { retry += 1 } }
            } else if highlights.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("Select text or use a verse’s actions to highlight it."))
            } else {
                ForEach(highlights) { highlight in
                    let ayah = verses.first { $0.id == highlight.source }
                    let available = ayah.map { highlight.isAvailable(in: $0.translations.merging(["arabic": $0.text]) { _, source in source }) } ?? false
                    Group {
                        if let ayah, let surah = surahs.first(where: { $0.id == ayah.surah }) {
                            NavigationLink {
                                QuranChapterView(surah: surah, initialVerse: ayah.number, reader: reader, highlight: highlight)
                            } label: { HighlightSummary(highlight: highlight, available: available) }
                                .accessibilityIdentifier("saved-verse-\(ayah.id)")
                        } else {
                            Button { editing = highlight } label: {
                                HighlightSummary(highlight: highlight, available: false)
                            }
                            .tint(.primary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit highlight", systemImage: "pencil") { editing = highlight }
                            .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Edit highlight", systemImage: "pencil") { editing = highlight }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Highlights")
        .sheet(item: $editing) { HighlightEditor(highlight: $0, existing: true) }
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
