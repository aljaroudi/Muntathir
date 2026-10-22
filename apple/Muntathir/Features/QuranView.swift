import SwiftUI

struct QuranView: View {
    @Environment(\.locale) private var locale
    @State private var reader = QuranReader()
    @State private var surahs: [QuranSurah] = []
    @State private var counts: [Int: Int] = [:]
    @State private var translations: [QuranTranslation] = []
    @State private var translationID = ""
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
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines), translationID: translationID, limit: limit, retry: retry)
    }

    private var matchingSurahs: [QuranSurah] {
        request.query.isEmpty ? surahs : surahs.filter { $0.matches(request.query) }
    }

    var body: some View {
        List {
            if request.query.isEmpty {
                Section {
                    NavigationLink {
                        QuranSavedVersesView(kind: .favorites, reader: reader, surahs: surahs, translations: translations, translationID: $translationID)
                    } label: { Label("Favorites", systemImage: "star") }
                        .accessibilityIdentifier("quran-favorites")
                    NavigationLink {
                        QuranSavedVersesView(kind: .notes, reader: reader, surahs: surahs, translations: translations, translationID: $translationID)
                    } label: { Label("Notes", systemImage: "note.text") }
                        .accessibilityIdentifier("quran-notes")
                }
            }
            if !matchingSurahs.isEmpty {
                Section("Surahs") {
                    ForEach(matchingSurahs) { surah in
                        NavigationLink {
                            QuranChapterView(surah: surah, reader: reader, translations: translations, translationID: $translationID)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(surah.id.formatted(.number.locale(locale))). \(surah.title(locale: locale))")
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
                                QuranVerseRow(ayah: ayah, translation: translations.first { $0.id == translationID }, preview: true)
                                NavigationLink {
                                    QuranChapterView(surah: surah, initialVerse: ayah.number, reader: reader, translations: translations, translationID: $translationID)
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
                QuranTranslationPicker(translations: translations, selection: $translationID)
            }
        }
        .onChange(of: query) { limit = 50 }
        .onChange(of: translationID) { limit = 50 }
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
                translations = catalog.translations
                surahs = catalog.surahs
                translationID = QuranTranslation.preferred(in: catalog.translations, locale: locale)?.id ?? ""
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
    let translations: [QuranTranslation]
    @Binding var selection: String
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker("Translation", selection: $selection) {
                Text("None").tag("")
                ForEach(translations) { translation in
                    Text(locale.localizedString(forIdentifier: translation.language) ?? translation.language)
                        .tag(translation.id)
                }
            }
        } label: {
            Label("Translation", systemImage: "character.bubble")
        }
        .accessibilityIdentifier("quran-translation-picker")
        .accessibilityValue(translations.first { $0.id == selection }?.translator ?? String(localized: "None"))
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
