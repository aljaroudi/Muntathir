import SwiftUI

struct SupplicationsView: View {
    let reader: HadithReader
    @Environment(\.locale) private var locale
    @Environment(\.hadithAssets) private var assets
    @State private var query = ""
    @State private var introductions: [HadithIntroduction] = []
    @State private var prayers: [Hadith] = []
    @State private var loading = true
    @State private var failed = false
    @State private var needsUpdate = false
    @State private var retry = 0

    private struct Search: Equatable {
        let query: String
        let retry: Int
    }

    var body: some View {
        List {
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
                if query.isEmpty {
                    ForEach(introductions) { introduction in
                        HadithIntroductionRow(introduction: introduction, reader: reader)
                    }
                }
                Section(prayers[0].chapter.bookTitle(locale: locale)) {
                    ForEach(prayers) { prayer in
                        NavigationLink {
                            HadithDetailView(initialID: prayer.id, reader: reader, query: query,
                                             orderedFallback: false, supplication: true)
                                .environment(\.hadithSession, nil)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(prayer.chapter.chapterTitle(locale: locale))
                                    .font(.headline)
                                ReadingTimeHint(words: prayer.readingWords)
                                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(prayer.arabicDisplay)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .environment(\.layoutDirection, .rightToLeft)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("supplication-\(prayer.number - 1)")
                    }
                }
            }
        }
        .navigationTitle("Supplications")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search supplications")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            NavigationLink {
                HadithSavedView(reader: reader, supplications: true)
                    .environment(\.hadithSession, nil)
            } label: {
                Label("Highlights", systemImage: "highlighter")
            }
        }
        .task(id: Search(query: query, retry: retry)) {
            loading = true
            failed = false
            needsUpdate = false
            do {
                if !query.isEmpty {
                    try await Task.sleep(for: .milliseconds(150))
                }
                introductions = try await reader.introductions(collectionID: Hadith.supplicationCollectionID)
                let results = try await reader.supplications(query: query)
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
