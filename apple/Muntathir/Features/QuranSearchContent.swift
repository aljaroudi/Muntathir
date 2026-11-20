import SwiftUI

struct QuranSearchContent: View {
    var submittedQuery: String
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
    @State private var highlights: [String: QuranSearchHighlight] = [:]
    @State private var matchingSurahs: [QuranSurah] = []

    private struct Request: Equatable {
        let query: String
        let online: Bool
        let surah: Int?
        let translationID: String
        let limit: Int
        let retry: Int
        let translationRevision: Int
    }

    private var request: Request {
        Request(query: submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines), online: !submittedQuery.isEmpty, surah: surah?.id, translationID: translationStore.activeID, limit: limit, retry: retry, translationRevision: translationStore.revision)
    }

    /// Inputs to surah title filtering; it reruns once per submitted search, never per render.
    private struct SurahFilter: Equatable {
        let query: String
        let surah: Int?
        let count: Int
    }

    private func refreshSurahMatches() {
        let query = request.query
        guard surah == nil else { matchingSurahs = []; return }
        matchingSurahs = query.isEmpty ? surahs : surahs.filter { $0.matches(query) }
    }

    var body: some View {
        List {
            if request.query.isEmpty, surah == nil {
                Section {
                    NavigationLink {
                        QuranSavedVersesView(reader: reader, surahs: surahs)
                    } label: { Label("Saved", systemImage: "bookmark") }
                        .accessibilityIdentifier("quran-saved")
                }
            }
            if !matchingSurahs.isEmpty {
                Section("Surahs") {
                    ForEach(matchingSurahs) { surah in
                        NavigationLink {
                            QuranReadingView(surah: surah, reader: reader)
                                .recordSearchOnOpen(submittedQuery, area: .quran)
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
                    }
                }
            }
            // Earlier results stay visible until the next search replaces them.
            if !results.isEmpty, !request.query.isEmpty {
                verseResults(results)
            }
            if loading, results.isEmpty || request.query.isEmpty {
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
            } else if loading {
                EmptyView()
            } else if !request.query.isEmpty, resultQuery == request.query, results.isEmpty, matchingSurahs.isEmpty {
                ContentUnavailableView.search(text: request.query)
                    .accessibilityIdentifier("local-search-empty")
            }
        }
        .readingBackground()
        .overlay(alignment: .top) {
            if loading, !results.isEmpty, !request.query.isEmpty {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: .circle)
                    .padding(.top, 8)
                    .accessibilityLabel("Loading Quran…")
            }
        }
        .onChange(of: SurahFilter(query: request.query, surah: surah?.id, count: surahs.count), initial: true) { refreshSurahMatches() }
        .onChange(of: submittedQuery) { limit = 50 }
        .onChange(of: translationStore.activeID) { limit = 50 }
        .task(id: request) { await load() }
    }

    private func verseResults(_ verses: [Ayah]) -> some View {
        Section("Verses") {
            ForEach(verses) { ayah in
                if let surah = surahs.first(where: { $0.id == ayah.surah }) {
                    let translation = QuranTranslation.catalog.first { $0.id == translationStore.activeID }
                    NavigationLink {
                        QuranReadingView(surah: surah, initialVerse: ayah.number, reader: reader, searchQuery: resultQuery)
                            .recordSearchOnOpen(submittedQuery, area: .quran)
                    } label: {
                        QuranVerseRow(ayah: ayah, translation: translation, searchQuery: resultQuery, preview: true, showsActions: false,
                                      highlight: highlights[ayah.id])
                            .contentShape(.rect)
                    }
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

    private func search(_ current: Request) async throws -> [Ayah] {
        if current.online, current.limit == 50 {
            let number = QuranSearchText.number(current.query)
            let remoteQuery = current.surah.flatMap { chapter in number.map { "\(chapter):\($0)" } } ?? current.query
            let exact = try QuranSearchText.reference(remoteQuery)
            if let exact, let count = counts[exact.surah], current.surah == nil || current.surah == exact.surah, exact.verse > count {
                throw QuranDatabaseError.invalidReference
            }
            do {
                guard let client = SemanticSearchClient.configured else { throw URLError(.unsupportedURL) }
                let matches = try await client.search(remoteQuery, kind: "quran", chapter: current.surah.map(String.init))
                var seen = Set<String>()
                let references = matches.compactMap { match -> String? in
                    guard case let .quran(chapter, verse) = match.reference,
                          current.surah == nil || chapter == current.surah,
                          exact == nil || (chapter == exact?.surah && verse == exact?.verse) else { return nil }
                    return "\(chapter):\(verse)"
                }.filter { seen.insert($0).inserted }
                let verses = try await reader.verses(references: references)
                let byID = Dictionary(uniqueKeysWithValues: verses.map { ($0.id, $0) })
                let found = references.compactMap { byID[$0] }.filter { exact != nil || QuranSearchText.isSearchableVerse($0.text) }
                if matches.isEmpty || !found.isEmpty {
                    return found
                }
            } catch {
                try Task.checkCancellation()
            }
        }
        return try await reader.search(current.query, translationID: current.translationID, limit: current.limit + 1, surah: current.surah, revision: current.translationRevision)
    }

    private func load() async {
        loading = true
        failed = false
        invalidReference = false
        if request.query.isEmpty || resultTranslationID != request.translationID {
            results = []
            hasMore = false
        }
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
                if current.surah == nil, let number = QuranSearchText.number(current.query) {
                    invalidReference = counts[number] == nil
                    highlights = [:]
                    results = []
                    hasMore = false
                    resultQuery = current.query
                } else {
                    let found = try await search(current)
                    let visible = Array(found.prefix(current.limit))
                    let prepared = try await reader.highlights(visible, query: current.query, translationID: current.translationID)
                    try Task.checkCancellation()
                    guard current == request else { return }
                    resultQuery = current.query
                    resultTranslationID = current.translationID
                    highlights = prepared
                    results = visible
                    hasMore = found.count > current.limit
                }
            }
            try Task.checkCancellation()
            loading = false
        } catch is CancellationError {
            // The replacement task owns the loading state.
        } catch QuranDatabaseError.invalidReference {
            guard !Task.isCancelled else { return }
            results = []
            highlights = [:]
            hasMore = false
            invalidReference = true
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            hasMore = false
            failed = true
            loading = false
        }
    }
}
