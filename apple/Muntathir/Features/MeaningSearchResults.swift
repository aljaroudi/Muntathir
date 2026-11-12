import SwiftUI

/// Changing the parent query/scope resets explicit online-search consent.
struct MeaningSearchResults<Item, Results: View>: View {
    let query: String
    var hasLocalResults = false
    var emptyIdentifier = "local-search-empty"
    let search: () async throws -> [Item]
    @ViewBuilder let resultsContent: ([Item]) -> Results
    @State private var attempt = 0
    @State private var results: [Item] = []
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        Group {
            if attempt == 0 {
                if !hasLocalResults {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                        .accessibilityIdentifier(emptyIdentifier)
                }
                if SemanticSearchClient.configured != nil, query.count <= 512 {
                    Button("Search by meaning") { loading = true; attempt += 1 }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("search-by-meaning")
                }
            } else if loading {
                ProgressView("Searching…")
            } else if failed {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("You can still search downloaded Quran and Hadith text offline.")
                } actions: {
                    Button("Try again") { loading = true; attempt += 1 }
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .accessibilityIdentifier(emptyIdentifier)
            } else {
                resultsContent(results)
            }
        }
        .task(id: attempt) {
            guard attempt > 0 else { return }
            failed = false
            do {
                let found = try await search()
                try Task.checkCancellation()
                results = found
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                failed = true
            }
        }
    }
}
