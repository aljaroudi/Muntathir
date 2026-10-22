import SwiftUI

struct QuranView: View {
    @Environment(\.locale) private var locale
    @State private var translationStore = QuranTranslationStore.shared
    @State private var reader = QuranReader()
    @State private var surahs: [QuranSurah] = []
    @State private var counts: [Int: Int] = [:]
    @State private var query = ""
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
        let translationID: String
        let limit: Int
        let retry: Int
        let translationRevision: Int
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines), translationID: translationStore.activeID, limit: limit, retry: retry, translationRevision: translationStore.revision)
    }

    private var matchingSurahs: [QuranSurah] {
        request.query.isEmpty ? surahs : surahs.filter { $0.matches(request.query) }
    }

    var body: some View {
        List {
            if request.query.isEmpty {
                Section {
                    NavigationLink {
                        QuranSavedVersesView(kind: .favorites, reader: reader, surahs: surahs)
                    } label: { Label("Favorites", systemImage: "star") }
                        .accessibilityIdentifier("quran-favorites")
                    NavigationLink {
                        QuranSavedVersesView(kind: .notes, reader: reader, surahs: surahs)
                    } label: { Label("Notes", systemImage: "note.text") }
                        .accessibilityIdentifier("quran-notes")
                }
            }
            if !matchingSurahs.isEmpty {
                Section("Surahs") {
                    ForEach(matchingSurahs) { surah in
                        NavigationLink {
                            QuranChapterView(surah: surah, reader: reader)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(surah.id, format: .number). \(surah.title(locale: locale))")
                                    .font(.headline)
                                if locale.language.languageCode?.identifier != "ar" {
                                    Text(surah.arabic).environment(\.layoutDirection, .rightToLeft)
                                }
                                Text("\(counts[surah.id] ?? 0) verses").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("quran-surah-\(surah.id)")
                    }
                }
            }
            if !results.isEmpty {
                Section("Verses") {
                    ForEach(results) { ayah in
                        if let surah = surahs.first(where: { $0.id == ayah.surah }) {
                            VStack(alignment: .leading, spacing: 8) {
                                QuranVerseRow(ayah: ayah, translation: QuranTranslation.catalog.first { $0.id == translationStore.activeID }, preview: true)
                                NavigationLink {
                                    QuranChapterView(surah: surah, initialVerse: ayah.number, reader: reader)
                                } label: { Label("Read verse", systemImage: "book") }
                                    .accessibilityIdentifier("quran-result-\(ayah.id)")
                            }
                        }
                    }
                    if hasMore {
                        Button("Load more") { limit += 50 }
                            .disabled(loading)
                    }
                }
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
                ContentUnavailableView("Invalid verse reference", systemImage: "number", description: Text("Enter a chapter and verse such as 2:255."))
            } else if matchingSurahs.isEmpty, results.isEmpty {
                ContentUnavailableView.search(text: request.query)
            }
        }
        .navigationTitle("The Holy Quran")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Surah, 2:255, or Quran text")
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuranTranslationPicker()
            }
        }
        .onChange(of: query) { limit = 50 }
        .onChange(of: translationStore.activeID) { limit = 50 }
        .task(id: request) { await load() }
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
                surahs = catalog.surahs
            }
            let current = request
            if !current.query.isEmpty {
                try await Task.sleep(for: .milliseconds(250))
                if let number = QuranSearchText.number(current.query) {
                    invalidReference = counts[number] == nil
                } else {
                    let found = try await reader.search(current.query, translationID: current.translationID, limit: current.limit + 1)
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

struct QuranTranslationPicker: View {
    @Environment(\.locale) private var locale
    @State private var store = QuranTranslationStore.shared

    var body: some View {
        Menu {
            Button { store.select("auto") } label: {
                Label("Auto", systemImage: store.selection == "auto" ? "checkmark" : "globe")
            }
            Button { store.select("") } label: {
                Label("None", systemImage: store.selection.isEmpty ? "checkmark" : "minus")
            }
            ForEach(QuranTranslation.catalog) { translation in
                Button { store.select(translation.id) } label: {
                    Label(locale.localizedString(forIdentifier: translation.language) ?? translation.language,
                          systemImage: symbol(for: translation.id))
                }
            }
            if let status = store.statuses[store.activeID] {
                switch status {
                case let .downloading(fraction):
                    if let fraction {
                        Text("Downloading \(fraction, format: .percent.precision(.fractionLength(0)))")
                    } else {
                        Text("Downloading…")
                    }
                case .failed:
                    Text("Translation unavailable")
                    Button("Try again") { store.retryDownload() }
                case .installed: EmptyView()
                }
            }
            let installed = QuranTranslation.catalog.filter { store.statuses[$0.id] == .installed }
            if !installed.isEmpty {
                Menu("Remove download") {
                    ForEach(installed) { translation in
                        Button(locale.localizedString(forIdentifier: translation.language) ?? translation.language, role: .destructive) {
                            Task { await store.remove(translation) }
                        }
                    }
                }
            }
        } label: {
            if case .downloading = store.statuses[store.activeID] {
                Label("Downloading translation", systemImage: "arrow.down.circle")
            } else {
                Label("Translation", systemImage: "character.bubble")
            }
        }
        .accessibilityIdentifier("quran-translation-picker")
        .accessibilityValue(QuranTranslation.catalog.first { $0.id == store.activeID }?.translator ?? String(localized: "None"))
    }

    private func symbol(for id: String) -> String {
        if store.selection == id {
            return "checkmark"
        }
        switch store.statuses[id] {
        case .installed: return "checkmark.circle"
        case .downloading: return "arrow.down.circle"
        case .failed: return "exclamationmark.circle"
        case nil: return "icloud.and.arrow.down"
        }
    }
}

struct QuranVerseRow: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ayah.id).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Verse \(ayah.id)"))
                Spacer()
                VerseActions(ayah: ayah, translation: translation)
            }
            AyahText(ayah: ayah)
                .lineLimit(preview ? 3 : nil)
            if let translation, let text = ayah.translations[translation.id] {
                Text(text)
                    .lineLimit(preview ? 3 : nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, Locale(identifier: translation.language).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                    .accessibilityIdentifier("quran-translation-\(ayah.id)")
            }
        }
        .padding(.vertical, 12)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
    }
}
