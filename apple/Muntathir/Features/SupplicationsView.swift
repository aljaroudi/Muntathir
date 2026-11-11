import SwiftUI

struct SupplicationsView: View {
    let reader: HadithReader
    @Environment(\.locale) private var locale
    @Environment(\.hadithAssets) private var assets
    @AppStorage("supplicationTranslation") private var translation = "auto"
    @State private var languages: [String] = []
    @State private var query = ""
    @State private var prayers: [Hadith] = []
    @State private var loading = true
    @State private var failed = false
    @State private var needsUpdate = false
    @State private var retry = 0

    private struct Search: Equatable {
        let query: String
        let retry: Int
        let translation: String
        let locale: String
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    NavigationLink {
                        HadithSavedView(reader: reader, supplications: true)
                            .environment(\.hadithSession, nil)
                    } label: {
                        Label("Saved", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("supplication-saved")
                }
            }
            if loading {
                ProgressView()
            } else if needsUpdate {
                ContentUnavailableView {
                    Label("This download needs an update.", systemImage: "arrow.down.circle")
                } actions: {
                    NavigationLink("Downloads") { DownloadsSettingsView() }
                }
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load supplications", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Try again") { Task { await assets?.refresh(); retry += 1 } }
                }
            } else if prayers.isEmpty {
                ContentUnavailableView("No supplications found", systemImage: "magnifyingglass")
                    .accessibilityIdentifier("supplications-empty")
            } else {
                ForEach(Hadith.supplicationCollectionIDs, id: \.self) { collectionID in
                    let collectionPrayers = prayers.filter { $0.collectionID == collectionID }
                    if let first = collectionPrayers.first {
                        Section(first.chapter.bookTitle(locale: locale)) {
                            ForEach(collectionPrayers) { prayer in
                                NavigationLink {
                                    HadithDetailView(initialID: prayer.id, reader: reader, query: query,
                                                     orderedFallback: false, supplication: true)
                                        .environment(\.hadithSession, nil)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(prayer.chapter.chapterTitle(locale: locale))
                                            .font(.headline)
                                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            ReadingTimeHint(words: prayer.readingWords)
                                        }
                                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            if let translation = prayer.translation {
                                                Text(HadithText.highlighted(translation.text, terms: QuranSearchText.terms(query)))
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                                    .environment(\.layoutDirection, translation.isRightToLeft ? .rightToLeft : .leftToRight)
                                            } else {
                                                Text(prayer.arabicDisplay)
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                                    .environment(\.layoutDirection, .rightToLeft)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .readingRowBackground()
                                .accessibilityIdentifier(prayer.collectionID == Hadith.supplicationCollectionID ? "supplication-\(prayer.number - 1)" : "supplication-\(prayer.source?.key ?? String(prayer.id))")
                            }
                        }
                    }
                }
            }
        }
        .readingBackground()
        .navigationTitle("Supplications")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search supplications")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            Menu {
                SupplicationTranslationPicker(languages: languages)
                ReadingBackgroundPicker()
            } label: {
                Label("Reading options", systemImage: "textformat")
            }
            .accessibilityIdentifier("supplication-reading-options")
        }
        .task(id: Search(query: query, retry: retry, translation: translation, locale: locale.identifier)) {
            loading = true
            failed = false
            needsUpdate = false
            do {
                if !query.isEmpty {
                    try await Task.sleep(for: .milliseconds(150))
                }
                languages = try await reader.translationLanguages()
                let results = try await reader.supplications(query: query, translation: translation, languages: [locale.identifier])
                try Task.checkCancellation()
                prayers = results
                loading = false
            } catch is CancellationError {
            } catch HadithDatabaseError.incompatible {
                guard !Task.isCancelled else { return }
                needsUpdate = true
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                loading = false
            }
        }
    }
}
