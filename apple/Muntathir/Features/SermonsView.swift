import SQLite3
import SwiftUI

private struct Sermon: Identifiable {
    struct Segment: Identifiable {
        let id, kind, text: String
    }

    struct Edition: Identifiable {
        let id, language, kind: String
        let credit: String?
        let aligned: [String: String]

        var label: String {
            switch kind {
            case "literal": String(localized: "Literal")
            case "simplified": String(localized: "Simplified")
            default: credit ?? ""
            }
        }
    }

    /// A sermon's text and translations, loaded only when it's opened.
    struct Content {
        let segments: [Segment]
        let editions: [Edition]
    }

    let id, title, speakerID: String

    var route: FigureRoute {
        .sermon(id: id, title: title, speakerID: speakerID)
    }

    /// Lists sermons without their text, so the list stays cheap as sermons are added.
    @concurrent static func load() async throws -> [Self] {
        try open().query("SELECT id, title, speaker_id FROM sermon ORDER BY id") { row in
            Self(id: QuranConnection.text(row, 0), title: QuranConnection.text(row, 1), speakerID: QuranConnection.text(row, 2))
        }
    }

    @concurrent func content() async throws -> Content {
        let db = try Self.open()
        let text = QuranConnection.text
        let segments = try db.query("SELECT id, kind, text FROM segment WHERE sermon = ? ORDER BY position", parameters: [id]) {
            Segment(id: text($0, 0), kind: text($0, 1), text: text($0, 2))
        }
        let editions = try db.query("SELECT id, language, kind, credit FROM edition WHERE sermon = ? ORDER BY position", parameters: [id]) { item in
            let key = text(item, 0)
            let pairs = try db.query("SELECT segment, text FROM translation WHERE sermon = ? AND edition = ?", parameters: [id, key]) {
                (text($0, 0), text($0, 1))
            }
            return Edition(id: key, language: text(item, 1), kind: text(item, 2),
                           credit: sqlite3_column_type(item, 3) == SQLITE_NULL ? nil : text(item, 3),
                           aligned: Dictionary(uniqueKeysWithValues: pairs))
        }
        return Content(segments: segments, editions: editions)
    }

    private static func open() throws -> QuranConnection {
        guard let url = Bundle.main.url(forResource: "sermons", withExtension: "db") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
    }
}

private struct SermonMatch: Identifiable {
    let segment, block, text: String
    let range: NSRange
    var id: String { "\(segment):\(block):\(range.location):\(range.length)" }

    static func find(_ content: Sermon.Content, editions: [Sermon.Edition], terms: [String]) -> [Self] {
        guard !terms.isEmpty else { return [] }
        return content.segments.flatMap { segment in
            let translations = editions.compactMap { edition in
                edition.aligned[segment.id].map { (edition.id, $0) }
            }
            return ([("arabic", segment.text)] + translations).flatMap { block, text in
                Set(SearchMatch.ranges(in: text, terms: terms)).sorted { $0.location < $1.location }.map {
                    Self(segment: segment.id, block: block, text: text, range: $0)
                }
            }
        }
    }
}

struct SermonsView: View {
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var contents: [String: Sermon.Content] = [:]
    @State private var sermons: [Sermon]?
    @State private var figures: FigureLibrary?
    @State private var failed = false

    var body: some View {
        AdaptiveSplit(restorationKey: "sermons", defaultSelection: sermons?.first.map(\.route)) { selection in
            list(selection: selection)
        }
    }

    private func list(selection: Binding<FigureRoute?>) -> some View {
        Group {
            if let sermons {
                let terms = QuranSearchText.queryTerms(query)
                let titles = Set(sermons.filter {
                    terms.isEmpty || !SearchMatch.ranges(in: $0.title, terms: terms).isEmpty
                }.map(\.id))
                let matches = contents.mapValues { collectionMatches($0, terms: terms) }
                AdaptiveList(selection: selection) {
                    AdaptiveLink(route: .sermonsSaved) { Label("Saved", systemImage: "bookmark") }
                    if !terms.isEmpty, titles.isEmpty, contents.count == sermons.count,
                       matches.values.allSatisfy(\.isEmpty) {
                        Text("No results")
                    }
                    ForEach(sermons) { sermon in
                        if titles.contains(sermon.id) {
                            // Value-based so the reader lives in the stack's path; a view-based push gets
                            // re-pushed when the speaker link appends a figure profile to the path.
                            AdaptiveLink(route: sermon.route) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: sermon.title)
                                    if let speaker = figures?.byID[sermon.speakerID] {
                                        Text(verbatim: speaker.title(locale)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("sermon-\(sermon.id)")
                        }
                        if let content = contents[sermon.id] {
                            ForEach(matches[sermon.id] ?? []) { match in
                                AdaptiveLink(route: .sermonPassage(id: sermon.id, title: sermon.title, speakerID: sermon.speakerID,
                                                                 segment: match.segment, edition: match.block == "arabic" ? nil : match.block, query: query)) {
                                    VStack(alignment: .leading) {
                                        let edition = content.editions.first { $0.id == match.block }
                                        Text(verbatim: sermon.title + " · " + (edition.map { sermonLanguage($0.language) + " · " + $0.label } ?? "العربية"))
                                        SearchMatchText(SearchMatch.preview(HadithText.highlighted(match.text, terms: terms), compact: true))
                                    }
                                }
                            }
                        }
                    }
                }
            } else if failed {
                Text("Sermons unavailable")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Sermons")
        .searchable(text: $query, placement: .alwaysVisible, prompt: "Search sermons")
        .task(id: query.isEmpty || sermons == nil) {
            guard !query.isEmpty, let sermons else { return }
            for sermon in sermons where contents[sermon.id] == nil {
                if let content = try? await sermon.content(), !Task.isCancelled { contents[sermon.id] = content }
            }
        }
        .task {
            do { sermons = try await Sermon.load() } catch { failed = true }
            figures = try? await FigureStore.shared.load().get()
        }
    }

    private func collectionMatches(_ content: Sermon.Content, terms: [String]) -> [SermonMatch] {
        var seen: Set<[String]> = []
        return SermonMatch.find(content, editions: content.editions, terms: terms).filter {
            seen.insert([$0.segment, $0.block]).inserted
        }
    }
}

struct SermonDestination: View {
    let id, title, speakerID: String
    var segment: String? = nil
    var edition: String? = nil
    var query = ""
    @State private var speaker: Figure?

    var body: some View {
        SermonReader(sermon: Sermon(id: id, title: title, speakerID: speakerID), speaker: speaker, initialSegment: segment, initialEdition: edition, initialQuery: query)
            .task {
                speaker = try? await FigureStore.shared.load().get().byID[speakerID]
            }
    }
}

private struct SermonReader: View {
    let sermon: Sermon
    let speaker: Figure?
    let initialSegment: String?
    let initialEdition: String?
    let initialQuery: String
    @State private var finding = false
    @State private var query = ""
    @State private var matchIndex = 0
    private var matches: [SermonMatch] {
        content.map { SermonMatch.find($0, editions: edition.map { [$0] } ?? [], terms: QuranSearchText.queryTerms(query)) } ?? []
    }
    @Environment(\.locale) private var locale
    @State private var content: Sermon.Content?
    @State private var failed = false
    @State private var selection: String?
    @State private var position: String?
    @State private var textSizePresented = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var edition: Sermon.Edition? {
        content?.editions.first { $0.id == selection }
    }

    var body: some View {
        let hits = matches
        let active = finding && hits.indices.contains(matchIndex) ? hits[matchIndex] : nil
        VStack(spacing: 0) {
            if finding {
                HStack {
                    TextField("Find in sermon", text: $query)
                    Text(hits.isEmpty ? "0" : "\(min(matchIndex + 1, hits.count)) / \(hits.count)")
                    Button { move(-1) } label: { Label("Previous match", systemImage: "chevron.up") }
                        .disabled(hits.isEmpty)
                    Button { move(1) } label: { Label("Next match", systemImage: "chevron.down") }
                        .disabled(hits.isEmpty)
                    Button("Done") { finding = false; query = "" }
                }
                .labelStyle(.iconOnly)
                .padding()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    header
                    if content == nil {
                        Group {
                            if failed {
                                Text("Sermons unavailable")
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(content?.segments ?? []) { segment in
                        VStack(alignment: .leading, spacing: 14) {
                            if segment.kind == "heading" {
                                passage(segment.text, segment: segment.id, block: "arabic", language: "ar", centered: true, foreground: .accentColor, active: active)
                                    .padding(.top, 12)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("arabic-\(segment.id)")
                            } else {
                                passage(segment.text, segment: segment.id, block: "arabic", language: "ar", foreground: segment.kind == "note" ? .secondary : nil, active: active)
                                    .accessibilityIdentifier("arabic-\(segment.id)")
                            }
                            if let edition, let text = edition.aligned[segment.id] {
                                passage(text, segment: segment.id, block: edition.id, language: edition.language, marked: true, foreground: .secondary, active: active)
                            }
                        }
                        .id(segment.id)
                    }
                }
                .scrollTargetLayout()
                .textSelection(.enabled)
                .padding(20)
                .readingColumn()
            }
            .scrollPosition(id: $position, anchor: .top)
        }
        .environment(\.searchMatchQuery, query)
        .onChange(of: query) { if finding { resetMatches() } }
        .onChange(of: selection) { if finding { resetMatches() } }
        .readingBackground()
        .task {
            do {
                content = try await sermon.content()
                selection = initialEdition
                query = initialQuery
                position = initialSegment
            } catch { failed = true }
        }
        .navigationTitle(sermon.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Picker(selection: $selection) {
                        Text(verbatim: "العربية").tag(String?.none)
                    } label: {
                        EmptyView()
                    }
                    ForEach(Set((content?.editions ?? []).map(\.language)).sorted(), id: \.self) { language in
                        Menu(sermonLanguage(language)) {
                            Picker(selection: $selection) {
                                ForEach((content?.editions ?? []).filter { $0.language == language }) { item in
                                    Text(item.label).tag(Optional(item.id))
                                }
                            } label: {
                                EmptyView()
                            }
                        }
                        .accessibilityIdentifier("sermon-language-\(language)")
                    }
                } label: {
                    Label(edition.map { sermonLanguage($0.language) + " · " + $0.label } ?? "العربية", systemImage: "character.book.closed")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("sermon-edition")
            }
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Button("Find in sermon", systemImage: "magnifyingglass") { finding = true }
                    ReadingSizeMenu(isPresented: $textSizePresented)
                    ArabicDiacriticsToggle()
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }
                .accessibilityIdentifier("reading-options")
                .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            DictionarySelectableText(text: sermon.title, heading: 1, centered: true)
                .accessibilityAddTraits(.isHeader)
            if let speaker {
                NavigationLink(value: FigureRoute.profile(speaker.id)) {
                    Text(verbatim: speaker.title(locale))
                        .font(.subheadline)
                }
                .accessibilityIdentifier("sermon-speaker")
            }
            Capsule()
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 44, height: 3)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.vertical, 8)
    }

    private func resetMatches() {
        matchIndex = 0
        if let first = matches.first { position = first.segment }
    }

    private func move(_ step: Int) {
        let hits = matches
        guard !hits.isEmpty else { return }
        matchIndex = (matchIndex + step + hits.count) % hits.count
        position = hits[matchIndex].segment
    }

    /// Lays out text in its own direction; `marked` adds a leading accent bar that sets translations apart from the Arabic.
    private func passage(_ text: String, segment: String, block: String, language: String, centered: Bool = false, marked: Bool = false, foreground: Color? = nil, active: SermonMatch?) -> some View {
        HighlightText(text: text, source: "sermon/\(sermon.id)/\(segment)", block: block, isHadith: true,
                      reference: sermon.title, arabic: language == "ar", centered: centered, heading: centered ? 2 : nil,
                      emphasizedMatch: active.flatMap {
                          $0.segment == segment && $0.block == block ? $0.range : nil
                      }, textColor: foreground)
            .multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.leading, marked ? 14 : 0)
            .overlay(alignment: .leading) {
                if marked {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: 2)
                }
            }
            .environment(\.layoutDirection, Locale.Language(identifier: language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}

struct SermonsSavedView: View {
    @Environment(\.quranUserStore) private var store
    @State private var sermons: [Sermon] = []

    var body: some View {
        SavedList(highlights: store?.highlights.filter { $0.source.hasPrefix("sermon/") } ?? [],
                  bookmarks: [], canOpen: { sermon(for: $0.source) != nil }, available: { _ in true }) { entry in
            if let sermon = sermon(for: entry.source), let segment = entry.source.split(separator: "/").last {
                SermonDestination(id: sermon.id, title: sermon.title, speakerID: sermon.speakerID,
                                  segment: String(segment), edition: entry.highlight?.block == "arabic" ? nil : entry.highlight?.block)
                    .environment(\.focusedHighlight, entry.highlight)
            }
        }
        .navigationTitle("Saved")
        .task { sermons = (try? await Sermon.load()) ?? [] }
    }

    private func sermon(for source: String) -> Sermon? {
        let parts = source.split(separator: "/")
        guard parts.count == 3 else { return nil }
        return sermons.first { $0.id == parts[1] }
    }
}

private func sermonLanguage(_ language: String) -> String {
    if language == "zh-CN" {
        return "简体中文"
    }
    return Locale(identifier: language).localizedString(forIdentifier: language) ?? language
}
