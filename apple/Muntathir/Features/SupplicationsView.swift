import SwiftUI

struct SupplicationsView: View {
    let reader: HadithReader
    @Environment(\.locale) private var locale
    @Environment(\.hadithAssets) private var assets
    @AppStorage("supplicationTranslation.v2") private var translation = "auto"
    @State private var languages: [String] = []
    @State private var query = ""
    @State private var submitted = ""
    @State private var prayers: [Hadith] = []
    /// The query `prayers` were loaded for; rows group and highlight by it while a newer search loads.
    @State private var resultQuery = ""
    @State private var loading = true
    @State private var failed = false
    @State private var needsUpdate = false
    @State private var retry = 0

    private struct Search: Equatable {
        let query: String
        let online: Bool
        let retry: Int
        let translation: String
        let locale: String
    }

    var body: some View {
        AdaptiveSplit(restorationKey: "supplications", defaultSelection: firstPrayer) { selection in
            list(selection: selection)
        }
    }

    private var firstPrayer: FigureRoute? {
        prayers.first.map { .supplication(id: $0.id, query: "") }
    }

    private func list(selection: Binding<FigureRoute?>) -> some View {
        let terms = QuranSearchText.queryTerms(resultQuery)
        return AdaptiveList(selection: selection) {
            if submitted.isEmpty {
                Section {
                    AdaptiveLink(route: .supplicationsSaved) {
                        Label("Saved", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("supplication-saved")
                }
            }
            if loading, prayers.isEmpty {
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
                ForEach(resultQuery.isEmpty ? Hadith.supplicationCollectionIDs : ["results"], id: \.self) { collectionID in
                    let collectionPrayers = resultQuery.isEmpty ? prayers.filter { $0.collectionID == collectionID } : prayers
                    if let first = collectionPrayers.first {
                        Section(resultQuery.isEmpty ? first.chapter.bookTitle(locale: locale) : "") {
                            ForEach(collectionPrayers) { prayer in
                                AdaptiveLink(route: .supplication(id: prayer.id, query: resultQuery), search: (resultQuery, .supplications)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(prayer.chapter.chapterTitle(locale: locale))
                                            .font(.headline)
                                        if resultQuery.isEmpty {
                                            ReadingTimeHint(words: prayer.readingWords)
                                        } else {
                                            let translated = prayer.translation.map { HadithText.highlighted($0.text, terms: terms) } ?? AttributedString()
                                            let blocks = [prayer.arabicDisplay, translated]
                                            let visible = SearchMatch.visibleBlocks(blocks, preferred: locale.language.languageCode?.identifier == "ar" ? 0 : 1)
                                            ForEach(visible, id: \.self) { index in
                                                SearchMatchText(SearchMatch.preview(blocks[index], compact: true))
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .environment(\.layoutDirection, index == 0 || prayer.translation?.isRightToLeft == true ? .rightToLeft : .leftToRight)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .accessibilityIdentifier(prayer.collectionID == Hadith.supplicationCollectionID ? "supplication-\(prayer.number - 1)" : "supplication-\(prayer.source?.key ?? String(prayer.id))")
                            }
                        }
                    }
                }
            }
        }
        .readingBackground()
        .overlay(alignment: .top) {
            // Earlier results stay visible until the next search replaces them.
            if loading, !prayers.isEmpty {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: .circle)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Supplications")
        .searchable(text: $query, placement: .alwaysVisible, prompt: "Search supplications")
        .searchHistory($query, area: .supplications)
        .submitsSearch($query, submitted: $submitted)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            Menu {
                TranslationPicker(supplicationLanguages: languages)
            } label: {
                Label("Reading options", systemImage: "textformat")
            }
            .accessibilityIdentifier("supplication-reading-options")
        }
        .task(id: Search(query: submitted, online: !submitted.isEmpty, retry: retry, translation: translation, locale: locale.identifier)) {
            loading = true
            failed = false
            needsUpdate = false
            do {
                languages = try await reader.translationLanguages()
                let current = submitted
                let results = try await search(current)
                try Task.checkCancellation()
                prayers = results
                resultQuery = current
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

    private func search(_ query: String) async throws -> [Hadith] {
        if !query.isEmpty, let client = SemanticSearchClient.configured {
            do {
                let hits = try await client.search(query, kind: "dua")
                if hits.isEmpty {
                    return []
                }
                let locators = hits.compactMap { hit -> String? in
                    guard case .dua = hit.reference else { return nil }
                    return hit.locator
                }
                let resolved = try await reader.supplications(query: query, translation: translation, languages: [locale.identifier], locators: locators)
                if !resolved.isEmpty {
                    return resolved
                }
            } catch {
                try Task.checkCancellation()
            }
        }
        return try await reader.supplications(query: query, translation: translation, languages: [locale.identifier])
    }
}
