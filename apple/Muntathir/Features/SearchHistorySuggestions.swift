import SwiftUI

private struct SearchHistorySuggestions: ViewModifier {
    @Binding var query: String
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
    func searchHistory(_ query: Binding<String>, area: SearchHistory.Area) -> some View {
        modifier(SearchHistorySuggestions(query: query, area: area))
    }

    func recordSearchOnOpen(_ query: String, area: SearchHistory.Area) -> some View {
        onAppear { SearchHistory.shared.record(query, in: area) }
    }

    /// Searches only run on submit: typing just edits the field, and clearing it resets the search.
    func submitsSearch(_ query: Binding<String>, submitted: Binding<String>) -> some View {
        onSubmit(of: .search) {
            submitted.wrappedValue = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: query.wrappedValue) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submitted.wrappedValue = ""
            }
        }
    }
}
