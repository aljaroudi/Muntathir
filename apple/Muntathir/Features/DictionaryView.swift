import SwiftUI

/// Search for Arabic words; results open the full entry from each source dictionary. Looking up
/// selected text (`showsSearch` off) shows that text's roots without a search field.
struct DictionaryView: View {
    var initialQuery = ""
    var showsSearch = true
    @State private var query = ""
    @State private var submitted = ""
    @State private var started = false
    @State private var roots: [String] = []
    /// The query `roots` belongs to, so the empty state doesn't flash while a search runs.
    @State private var searched: String?
    @State private var failed = false
    /// An on-device guess when lookup finds no root for a single word; see `DictionaryRootSuggester`.
    @State private var suggestion: String?
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
        .navigationTitle(showsSearch ? Text("Arabic Dictionary") : Text(verbatim: initialQuery))
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
        return Group {
            // A looked-up word almost always has one root, so its definitions open directly; other
            // readings of the spelling are offered from there.
            if !showsSearch, searched == submitted, words.count == 1, let first = roots.first {
                DictionaryEntryView(root: first, alternatives: Array(roots.dropFirst()))
            } else {
                list(words: words, bookmarks: bookmarks)
            }
        }
        .modifier(DictionarySearchField(enabled: showsSearch, query: $query, submitted: $submitted))
        .task(id: Request(query: submitted, revision: assets.revision)) {
            failed = false
            suggestion = nil
            guard !submitted.isEmpty else { roots = []; searched = nil; return }
            do {
                let result = try await assets.reader.search(submitted)
                try Task.checkCancellation()
                roots = result
                searched = submitted
                guard result.isEmpty, words.count == 1, DictionaryRootSuggester.isAvailable else { return }
                let candidates = try await assets.reader.candidateRoots(for: submitted)
                let root = await DictionaryRootSuggester.shared.suggest(for: DictionaryReader.spell(submitted), candidates: candidates)
                try Task.checkCancellation()
                suggestion = root
            } catch {
                if !Task.isCancelled {
                    failed = true
                }
            }
        }
    }

    private func list(words: [String], bookmarks: [String]) -> some View {
        List {
            if submitted.isEmpty {
                if !bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(bookmarks, id: \.self) { root in rootLink(root) }
                    }
                }
            } else if searched == submitted {
                if !roots.isEmpty {
                    Section("Roots") {
                        ForEach(roots, id: \.self) { root in rootLink(root) }
                    }
                }
                if let suggestion {
                    Section {
                        rootLink(suggestion)
                    } header: {
                        Text("Suggested Root")
                    } footer: {
                        Text("This word isn’t in the dictionaries’ word lists. Its root was inferred on this device and may be wrong.")
                    }
                }
                if words.count > 1 {
                    Section("Words") {
                        ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                            if showsSearch {
                                Button(word) { search(word) }
                            } else {
                                NavigationLink(word) { DictionaryView(initialQuery: word, showsSearch: false) }
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
            } else if searched == submitted, !submitted.isEmpty, roots.isEmpty, suggestion == nil, words.count < 2 {
                ContentUnavailableView.search(text: submitted)
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
        if showsSearch {
            SearchHistory.shared.record(value, in: .dictionary)
        }
    }

    private struct Request: Equatable {
        let query: String
        let revision: Int
    }
}

/// The dictionary tool's search field; lookups of selected text have none.
private struct DictionarySearchField: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    @Binding var submitted: String

    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $query, placement: .alwaysVisible, prompt: "Search")
                .searchHistory($query, area: .dictionary)
                .submitsSearch($query, submitted: $submitted)
        } else {
            content
        }
    }
}

/// Every source's definition of one root.
struct DictionaryEntryView: View {
    let root: String
    /// Other roots the looked-up spelling can come from, less likely than `root`.
    var alternatives: [String] = []
    @State private var definitions: [DictionaryReader.Definition] = []
    @State private var failed = false
    @State private var lookup: Lookup?
    @AppStorage("lexicon.bookmarks") private var bookmarksData = Data()
    /// Nil hides the summary; empty while it starts.
    @State private var summary: [DictionarySummarizer.Passage]?
    @AppStorage(DictionarySummarySection.setting) private var summaries = true
    private let assets = AssetPackUpdates.shared.dictionary

    private struct Lookup: Hashable {
        let text: String
    }

    var body: some View {
        let bookmarks = DictionaryBookmarks.decode(bookmarksData)
        let saved = bookmarks.contains(root)
        List {
            if !alternatives.isEmpty {
                Section("Other Possible Roots") {
                    ForEach(alternatives, id: \.self) { other in
                        NavigationLink {
                            DictionaryEntryView(root: other)
                        } label: {
                            Text(other).readingText(arabic: true, hadith: true, adjustable: false)
                        }
                    }
                }
            }
            if summaries, let summary {
                DictionarySummarySection(passages: summary) { summaries = false }
            }
            ForEach(definitions) { entry in
                // A source filing the root under another spelling (سمو for سما) names that heading.
                Section(entry.root == root ? DictionaryReader.sources[entry.source] : "\(DictionaryReader.sources[entry.source]) · \(entry.root)") {
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
        .navigationDestination(item: $lookup) { DictionaryView(initialQuery: $0.text, showsSearch: false) }
        .task(id: "\(root)|\(assets.revision)") {
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
        .task(id: "\(root)|\(assets.revision)|\(definitions.count)|\(summaries)") {
            summary = nil
            guard summaries, !definitions.isEmpty, DictionarySummarizer.isAvailable else { return }
            summary = []
            let result = await DictionarySummarizer.shared.summarize(root: root, definitions: definitions, revision: assets.revision) { partial in
                await MainActor.run {
                    if !Task.isCancelled {
                        summary = partial
                    }
                }
            }
            guard !Task.isCancelled else { return }
            summary = result
        }
    }
}

/// Key passages of a root's definitions; `DictionaryEntryView` runs the summary so rows can change mid-stream.
struct DictionarySummarySection: View {
    static let setting = "lexicon.summaries"
    let passages: [DictionarySummarizer.Passage]
    let turnOff: () -> Void

    var body: some View {
        Section {
            if passages.isEmpty {
                ProgressView("Summarizing…")
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(passages.enumerated()), id: \.offset) { _, passage in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: passage.text)
                        .readingText(arabic: true, hadith: true, adjustable: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: DictionaryReader.sources[passage.source])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Turn Off Summaries", systemImage: "text.badge.xmark", action: turnOff)
                }
            }
        } header: {
            Text("Summary")
        }
        .accessibilityIdentifier("dictionary-summary")
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
                    DictionaryView(initialQuery: item.text, showsSearch: false)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { selection = nil } }
                        }
                }
                .presentationDetents([.medium, .large])
                .frame(minWidth: 300, minHeight: 360)
            }
    }
}
