import SwiftUI

struct QuranSearchContent: View {
    @Binding var query: String
    @Environment(\.locale) private var locale
    @State private var translationStore = QuranTranslationStore.shared
    let reader: QuranReader
    var surah: QuranSurah?
    @State private var surahs: [QuranSurah] = []
    @State private var counts: [Int: Int] = [:]
    @State private var readingWords: [Int: Int] = [:]
    @State private var results: [Ayah] = []
    @State private var limit = 50
    @State private var loading = true
    @State private var failed = false
    @State private var invalidReference = false
    @State private var hasMore = false
    @State private var retry = 0
    @State private var resultQuery = ""
    @State private var resultTranslationID = ""

    private struct Request: Equatable {
        let query: String
        let surah: Int?
        let translationID: String
        let limit: Int
        let retry: Int
        let translationRevision: Int
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines), surah: surah?.id, translationID: translationStore.activeID, limit: limit, retry: retry, translationRevision: translationStore.revision)
    }

    private var matchingSurahs: [QuranSurah] {
        guard surah == nil else { return [] }
        return request.query.isEmpty ? surahs : surahs.filter { $0.matches(request.query) }
    }

    var body: some View {
        List {
            if request.query.isEmpty, surah == nil {
                Section {
                    NavigationLink {
                        QuranSavedVersesView(reader: reader, surahs: surahs)
                    } label: { Label("Saved", systemImage: "bookmark") }
                        .accessibilityIdentifier("quran-saved")
                        .readingRowBackground()
                }
            }
            if !matchingSurahs.isEmpty {
                Section("Surahs") {
                    ForEach(matchingSurahs) { surah in
                        NavigationLink {
                            QuranReadingView(surah: surah, reader: reader)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(surah.id, format: .number).fixedSize()
                                    Text(verbatim: ".")
                                    Text(surah.title(locale: locale)).padding(.leading, 6)
                                }
                                .font(.headline)
                                .accessibilityElement(children: .combine)
                                if locale.language.languageCode?.identifier != "ar" {
                                    Text(surah.arabic).environment(\.layoutDirection, .rightToLeft)
                                }
                                HStack(spacing: 12) {
                                    Text("\(counts[surah.id] ?? 0) verses").font(.caption).foregroundStyle(.secondary)
                                    if request.query.isEmpty {
                                        ReadingTimeHint(words: readingWords[surah.id] ?? 0, showsIcon: true)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("quran-surah-\(surah.id)")
                        .readingRowBackground()
                    }
                }
            }
            if !results.isEmpty {
                verseResults(results)
            }
            if loading {
                ProgressView("Loading Quran…").frame(maxWidth: .infinity)
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Please try again.")
                } actions: {
                    Button("Try again") { retry += 1 }
                }
            } else if invalidReference {
                ContentUnavailableView {
                    Label("Invalid verse reference", systemImage: "number")
                } description: {
                    if surah == nil {
                        Text("Enter a chapter and verse such as 2:255.")
                    } else {
                        Text("Enter a valid verse number in this chapter.")
                    }
                }
            } else if !request.query.isEmpty, resultQuery == request.query, matchingSurahs.isEmpty, results.isEmpty {
                MeaningSearchResults(query: request.query) {
                    guard let client = SemanticSearchClient.configured else { throw URLError(.unsupportedURL) }
                    let matches = try await client.search(request.query, kind: "quran", chapter: request.surah.map(String.init))
                    let references = matches.compactMap { match -> String? in
                        guard case let .quran(chapter, verse) = match.reference,
                              request.surah == nil || chapter == request.surah else { return nil }
                        return "\(chapter):\(verse)"
                    }
                    let verses = try await reader.verses(references: references)
                    let byID = Dictionary(uniqueKeysWithValues: verses.map { ($0.id, $0) })
                    return references.compactMap { byID[$0] }
                } resultsContent: { verses in
                    verseResults(verses)
                }
                .id("\(request.surah ?? 0):\(request.query):\(request.translationID):\(request.translationRevision)")
            }
        }
        .readingBackground()
        .onChange(of: query) { limit = 50 }
        .onChange(of: translationStore.activeID) { limit = 50 }
        .task(id: request) { await load() }
    }

    private func verseResults(_ verses: [Ayah]) -> some View {
        Section("Verses") {
            ForEach(verses) { ayah in
                if let surah = surahs.first(where: { $0.id == ayah.surah }) {
                    let translation = QuranTranslation.catalog.first { $0.id == translationStore.activeID }
                    NavigationLink {
                        QuranReadingView(surah: surah, initialVerse: ayah.number, reader: reader)
                    } label: {
                        QuranVerseRow(ayah: ayah, translation: translation, preview: true, showsActions: false)
                            .contentShape(.rect)
                    }
                    .readingRowBackground()
                    .accessibilityIdentifier("quran-result-\(ayah.id)")
                    .accessibilityLabel(Text("Verse \(QuranReference.display(ayah.id, locale: locale))"))
                    .accessibilityValue(ayah.text)
                    .overlay(alignment: .topTrailing) {
                        VerseActions(ayah: ayah, translation: translation)
                            .buttonStyle(.borderless)
                            .padding(.top, 12)
                            .padding(.trailing, 28)
                    }
                }
            }
            if hasMore {
                Button("Load more") { limit += 50 }
                    .disabled(loading)
            }
        }
    }

    private func load() async {
        loading = true
        failed = false
        invalidReference = false
        if resultQuery != request.query || resultTranslationID != request.translationID {
            results = []
        }
        hasMore = false
        do {
            if surahs.isEmpty {
                let catalog = try await reader.catalog()
                try Task.checkCancellation()
                counts = catalog.counts
                readingWords = catalog.readingWords
                surahs = catalog.surahs
            }
            let current = request
            if !current.query.isEmpty {
                try await Task.sleep(for: .milliseconds(250))
                if current.surah == nil, let number = QuranSearchText.number(current.query) {
                    invalidReference = counts[number] == nil
                } else {
                    let found = try await reader.search(current.query, translationID: current.translationID, limit: current.limit + 1, surah: current.surah)
                    try Task.checkCancellation()
                    guard current == request else { return }
                    resultQuery = current.query
                    resultTranslationID = current.translationID
                    results = Array(found.prefix(current.limit))
                    hasMore = found.count > current.limit
                }
            }
            try Task.checkCancellation()
            loading = false
        } catch is CancellationError {
            // The replacement task owns the loading state.
        } catch QuranDatabaseError.invalidReference {
            guard !Task.isCancelled else { return }
            invalidReference = true
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}
