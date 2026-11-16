import SwiftUI

private struct SearchHistorySuggestions: ViewModifier {
    let query: String
    let area: SearchHistory.Area
    @State private var history = SearchHistory.shared

    func body(content: Content) -> some View {
        content
            .searchSuggestions {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !history.queries(in: area).isEmpty
                {
                    Section("Recent searches") {
                        ForEach(history.queries(in: area), id: \.self) { recent in
                            HStack {
                                Label(recent, systemImage: "clock")
                                    .searchCompletion(recent)
                                    .accessibilityIdentifier("search-history-" + recent)
                                Spacer()
                                Button {
                                    history.remove(recent, from: area)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove search")
                                .accessibilityIdentifier("search-history-remove-" + recent)
                            }
                        }
                        Button("Clear history", role: .destructive) { history.clear(area) }
                            .accessibilityIdentifier("search-history-clear")
                    }
                }
            }
            .onSubmit(of: .search) { history.record(query, in: area) }
    }
}

extension View {
    func searchHistory(_ query: String, area: SearchHistory.Area) -> some View {
        modifier(SearchHistorySuggestions(query: query, area: area))
    }

    func recordSearchOnOpen(_ query: String, area: SearchHistory.Area) -> some View {
        onAppear { SearchHistory.shared.record(query, in: area) }
    }
}
