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

    private struct Request: Equatable {
        let ids: [String]
        let retry: Int
        let translationRevision: Int
    }

    private var highlights: [ReadingHighlight] {
        store?.highlights.filter { !$0.isHadith } ?? []
    }

    private var bookmarks: [ReadingBookmark] {
        store?.bookmarks.filter { !$0.isHadith } ?? []
    }

    private var savedIDs: [String] {
        Array(Set(highlights.map(\.source) + bookmarks.map(\.source))).sorted()
    }

    var body: some View {
        SavedList(highlights: highlights, bookmarks: bookmarks, canOpen: { entry in
            verses.contains { ayah in ayah.id == entry.source && surahs.contains(where: { $0.id == ayah.surah }) }
        }, available: { highlight in
            verses.first { $0.id == highlight.source }.map {
                highlight.isAvailable(in: $0.translations.merging(["arabic": $0.text]) { _, source in source })
            } ?? false
        }) { entry in
            if let ayah = verses.first(where: { $0.id == entry.source }),
               let surah = surahs.first(where: { $0.id == ayah.surah })
            {
                QuranReadingView(surah: surah, initialVerse: ayah.number, reader: reader, highlight: entry.highlight)
            }
        }
        .accessibilityHidden(store?.unavailable != false || loading || failed)
        .allowsHitTesting(store?.unavailable == false && !loading && !failed)
        .overlay {
            if store?.unavailable != false || loading || failed {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    Group {
                        if store?.unavailable != false {
                            ContentUnavailableView {
                                Label("Saved unavailable", systemImage: "exclamationmark.triangle")
                            } description: { Text("Your saved data could not be opened. Please try again.") }
                                actions: { Button("Try again") { store?.reopen() } }
                        } else if loading {
                            ProgressView("Loading Quran…")
                        } else if failed {
                            ContentUnavailableView {
                                Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                            } actions: { Button("Try again") { retry += 1 } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved")
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
