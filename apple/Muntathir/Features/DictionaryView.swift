import SwiftUI

/// Search for Arabic words; results open the full entry from each source dictionary.
struct DictionaryView: View {
    var initialQuery = ""
    @State private var query = ""
    @State private var submitted = ""
    @State private var started = false
    @State private var matches = DictionaryReader.Matches()
    /// The query `matches` belongs to, so the empty state doesn't flash while a search runs.
    @State private var searched: String?
    @State private var failed = false
    @AppStorage("lexicon.bookmarks") private var bookmarksData = Data()
    private let assets = AssetPackUpdates.shared.dictionary

    var body: some View {
        Group {
            if assets.state == .ready {
                results
            } else {
                download
            }
        }
        .navigationTitle("Arabic Dictionary")
        .onAppear {
            guard !started else { return }
            started = true
            if !initialQuery.isEmpty {
                search(initialQuery)
            }
        }
        .task { await assets.refresh() }
        .task { await assets.monitor() }
    }

    private var results: some View {
        let words = submitted.split(whereSeparator: \.isWhitespace).map(String.init)
        let bookmarks = DictionaryBookmarks.decode(bookmarksData)
        return List {
            if submitted.isEmpty {
                if !bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(bookmarks, id: \.self) { root in rootLink(root) }
                    }
                }
            } else if searched == submitted {
                if !matches.roots.isEmpty {
                    Section("Roots") {
                        ForEach(matches.roots, id: \.self) { root in rootLink(root) }
                    }
                }
                if words.count > 1 {
                    Section("Words") {
                        ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                            Button(word) { search(word) }
                        }
                    }
                }
                if !matches.passages.isEmpty {
                    Section("Mentions") {
                        ForEach(matches.passages, id: \.self) { match in
                            NavigationLink {
                                DictionaryEntryView(root: match.root, source: match.source)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.root).font(.headline)
                                    Text(match.preview).foregroundStyle(.secondary).lineLimit(2)
                                    Text(DictionaryReader.sources[match.source]).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if failed {
                ContentUnavailableView("Unable to read dictionary", systemImage: "exclamationmark.triangle")
            } else if submitted.isEmpty, bookmarks.isEmpty {
                ContentUnavailableView("Arabic Dictionary", systemImage: "character.book.closed",
                                       description: Text("Search for a word to see its root and meanings."))
            } else if searched == submitted, !submitted.isEmpty, matches.roots.isEmpty, matches.passages.isEmpty, words.count < 2 {
                ContentUnavailableView.search(text: submitted)
            }
        }
        .searchable(text: $query, placement: .alwaysVisible, prompt: "Search")
        .searchHistory($query, area: .dictionary)
        .submitsSearch($query, submitted: $submitted)
        .task(id: Request(query: submitted, revision: assets.revision)) {
            failed = false
            guard !submitted.isEmpty else { matches = .init(); searched = nil; return }
            do {
                let result = try await assets.reader.search(submitted)
                try Task.checkCancellation()
                matches = result
                searched = submitted
            } catch {
                if !Task.isCancelled {
                    failed = true
                }
            }
        }
    }

    private var download: some View {
        ContentUnavailableView {
            Label("Arabic Dictionary", systemImage: "character.book.closed")
        } description: {
            switch assets.state {
            case .failed: Text("Unable to download. Please try again.")
            case .incompatible: Text("This download needs an update.")
            case .checking, .downloading: EmptyView()
            default: Text("Look up words offline.")
            }
        } actions: {
            if assets.state == .downloading {
                AssetDownloadProgress(progress: assets.progress, preparing: assets.progress == nil)
                    .frame(maxWidth: 300)
            } else if assets.busy || assets.state == .checking {
                ProgressView()
            } else {
                AssetDownloadButton(pack: "lexicon", retry: assets.state == .failed || assets.state == .incompatible) {
                    Task { await assets.download() }
                }
            }
        }
    }

    private func rootLink(_ root: String) -> some View {
        NavigationLink {
            DictionaryEntryView(root: root)
        } label: {
            Text(root).readingText(arabic: true, hadith: true, adjustable: false)
        }
    }

    private func search(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        query = value
        submitted = value
        SearchHistory.shared.record(value, in: .dictionary)
    }

    private struct Request: Equatable {
        let query: String
        let revision: Int
    }
}

/// Every source's definition of one root, with the source that matched a search listed first.
struct DictionaryEntryView: View {
    let root: String
    var source: Int?
    @State private var definitions: [DictionaryReader.Definition] = []
    @State private var failed = false
    @State private var lookup: Lookup?
    @AppStorage("lexicon.bookmarks") private var bookmarksData = Data()
    private let assets = AssetPackUpdates.shared.dictionary

    private struct Lookup: Hashable {
        let text: String
    }

    var body: some View {
        let bookmarks = DictionaryBookmarks.decode(bookmarksData)
        let saved = bookmarks.contains(root)
        List {
            ForEach(definitions.sorted { ($0.id == source ? -1 : $0.id) < ($1.id == source ? -1 : $1.id) }) { entry in
                Section(DictionaryReader.sources[entry.id]) {
                    DictionarySelectableText(text: entry.body)
                }
            }
        }
        .overlay {
            if failed {
                ContentUnavailableView("Unable to read dictionary", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(root)
        .toolbar {
            Button(saved ? "Remove Bookmark" : "Bookmark", systemImage: saved ? "bookmark.fill" : "bookmark") {
                let next = saved ? bookmarks.filter { $0 != root } : [root] + bookmarks
                bookmarksData = (try? JSONEncoder().encode(next)) ?? bookmarksData
            }
        }
        // Looking up text inside an entry searches on this stack instead of opening another sheet.
        .environment(\.lookupSelection) { lookup = Lookup(text: $0) }
        .navigationDestination(item: $lookup) { DictionaryView(initialQuery: $0.text) }
        .task(id: assets.revision) {
            failed = false
            guard assets.state == .ready else { return }
            do {
                let rows = try await assets.reader.entry(root)
                try Task.checkCancellation()
                definitions = rows
            } catch {
                if !Task.isCancelled {
                    failed = true
                }
            }
        }
    }
}

private enum DictionaryBookmarks {
    static func decode(_ data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

struct DictionaryDownloadRow: View {
    private let assets = AssetPackUpdates.shared.dictionary
    var body: some View {
        switch assets.state {
        case .checking: ProgressView()
        case .downloading: ProgressView(value: assets.progress?.fractionCompleted)
        case .ready:
            LabeledContent { AssetSizeText(bytes: assets.installedBytes) } label: { Text("Arabic Dictionary") }
                .removeDownloadControl("Remove download", id: "downloads-remove-lexicon") { Task { await assets.remove() } }
        default:
            LabeledContent {
                AssetDownloadButton(pack: "lexicon", retry: assets.state == .failed || assets.state == .incompatible) {
                    Task { await assets.download() }
                }
            } label: { Text("Arabic Dictionary") }
        }
    }
}

struct DictionarySelectableText: View {
    let text: String
    var arabic = true
    var heading: Int?
    var centered = false
    @AppStorage("readingSizePercent") private var percent = 100
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    @ScaledMetric(relativeTo: .title2) private var arabicSize = 28

    var body: some View {
        SelectableHighlightText(attributed: HighlightTextContent.attributed(text: text, markdown: nil, arabic: arabic,
                                                                            hadith: arabic, heading: heading, size: (arabic ? arabicSize : bodySize) * CGFloat(min(160, max(80, percent))) / 100, alignment: centered ? .center : .natural), highlights: [], block: "", focused: nil,
                                differentiate: false, select: { _ in }, tap: { _ in }, canHighlight: { _ in false })
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension EnvironmentValues {
    @Entry var lookupSelection: (String) -> Void = { _ in }
}

struct DictionaryLookupHost: ViewModifier {
    private struct Selection: Identifiable {
        let id = UUID()
        let text: String
    }

    @State private var selection: Selection?

    func body(content: Content) -> some View {
        content.environment(\.lookupSelection) { selection = Selection(text: $0) }
            .sheet(item: $selection) { item in
                NavigationStack {
                    DictionaryView(initialQuery: item.text)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { selection = nil } }
                        }
                }
                .presentationDetents([.medium, .large])
                .frame(minWidth: 300, minHeight: 360)
            }
    }
}
