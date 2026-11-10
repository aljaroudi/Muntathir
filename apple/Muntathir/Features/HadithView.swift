import SwiftUI

struct HadithView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hadithAssets) private var assets
    @Environment(\.hadithSession) private var session
    @State private var restored = false
    @State private var visibleRows: [String: CGFloat] = [:]
    @State private var restoredRow: String?
    @State private var restoringList = true
    @State private var listOffset: Double = 0
    @Environment(\.locale) private var locale
    @FocusState private var searchFocused: Bool
    let reader: HadithReader
    var initialRequest: HadithRequest?
    var restoredState: HadithSessionState?
    @State private var collection: HadithCollection?
    @State private var collectionRestoration: HadithSessionState?
    @State private var catalog: [HadithCollection] = []
    @State private var introductions: [HadithIntroduction] = []
    @State private var chapters: [HadithChapter] = []
    @State private var request = HadithRequest()
    @State private var searchText = ""
    @State private var completedRequest: HadithRequest?
    @State private var page = HadithPage(rows: [], hasMore: false)
    @State private var history: [HadithCursor] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var selected: Hadith?
    @State private var route: SearchRoute?

    private struct SearchRoute: Identifiable, Hashable {
        let id = UUID()
        let request: HadithRequest
        var restoresChapter = false
    }

    private struct LoadRequest: Equatable {
        let search: HadithRequest
        let retry: Int
    }

    private var query: String {
        request.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsNarrations: Bool {
        HadithSearch.chapter(query) == nil && (!query.isEmpty || request.chapterID != nil)
    }

    private var matchingBooks: [HadithCollection] {
        guard request.collectionID == nil, HadithSearch.number(query) == nil,
              HadithSearch.chapter(query) == nil else { return [] }
        return catalog.filter { query.isEmpty || $0.matches(query) }
    }

    private var matchingChapters: [HadithChapter] {
        guard HadithSearch.number(query) == nil else { return [] }
        if let number = HadithSearch.chapter(query) {
            return chapters.filter { $0.index == number - 1 && (request.chapterID == nil || $0.id == request.chapterID) }
        }
        if query.isEmpty, request.collectionID == nil || request.chapterID != nil {
            return []
        }
        return chapters.filter { (request.chapterID == nil || $0.id == request.chapterID) && $0.matches(query) }
    }

    private var selectedBook: HadithCollection? {
        catalog.first { $0.id == request.collectionID }
    }

    private var navigationTitle: String {
        if let chapter = chapters.first(where: { $0.id == request.chapterID }) {
            let title = chapter.chapterTitle(locale: locale)
            if !title.isEmpty {
                return title
            }
        }
        return selectedBook?.title(locale: locale) ?? String(localized: "Hadith")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !matchingBooks.isEmpty {
                    ForEach(HadithBookGroup.allCases) { group in
                        let books = matchingBooks.filter { $0.group == group }.sorted {
                            $0.title(locale: locale).compare($1.title(locale: locale), options: .numeric, locale: locale) == .orderedAscending
                        }
                        if !books.isEmpty {
                            Section(group.title) {
                                ForEach(books) { book in
                                    Button { searchFocused = false; collectionRestoration = nil; collection = book } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(book.title(locale: locale)).font(.headline)
                                            if locale.language.languageCode?.identifier != "ar" {
                                                Text(book.arabic).environment(\.layoutDirection, .rightToLeft)
                                            }
                                            Text("\(book.count, format: .number) narrations").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                    }
                                    .accessibilityIdentifier("hadith-book-\(book.id)")
                                    .tint(.primary)
                                    .listRowBackground(HadithBookStyle.background(for: book.id))
                                    .modifier(HadithListAnchor(id: "book:" + book.id, visibleRows: $visibleRows))
                                    .id("book:" + book.id)
                                }
                            }
                        }
                    }
                }
                if query.isEmpty, !introductions.isEmpty {
                    Section("Introduction") {
                        ForEach(introductions) { introduction in
                            HadithIntroductionRow(introduction: introduction, reader: reader)
                                .listRowBackground(HadithBookStyle.background(for: request.collectionID ?? ""))
                                .modifier(HadithListAnchor(id: "introduction:\(introduction.id)", visibleRows: $visibleRows))
                                .id("introduction:\(introduction.id)")
                        }
                    }
                }
                chapterResults
                if showsNarrations, !page.rows.isEmpty {
                    narrationResults(page.rows, orderedFallback: page.usedOrderedFallback)
                }
                if loading {
                    ProgressView("Loading Hadith…").frame(maxWidth: .infinity)
                } else if failed {
                    HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
                } else if !query.isEmpty, completedRequest == request, page.rows.isEmpty, matchingBooks.isEmpty, matchingChapters.isEmpty {
                    Group {
                        MeaningSearchResults(query: query, emptyIdentifier: "hadith-empty-results") {
                            guard let client = SemanticSearchClient.configured else { throw URLError(.unsupportedURL) }
                            let scope = try await reader.meaningSearchScope(request)
                            let matches = try await client.search(query, kind: "hadith", sources: scope.sources, chapter: scope.chapter)
                            var narrations: [Hadith] = []
                            for match in matches {
                                guard case let .hadith(book, chapter, number) = match.reference,
                                      let id = try await reader.resolveSearch(book: book, chapter: chapter, number: number) else { continue }
                                try Task.checkCancellation()
                                let narration = try await reader.detail(id: id).narration
                                if !narration.isSupplication {
                                    narrations.append(narration)
                                }
                            }
                            return narrations
                        } resultsContent: { narrations in
                            narrationResults(narrations)
                        }
                        .id(request)
                        if request.collectionID != nil {
                            Button("Search all books") {
                                searchFocused = false
                                route = SearchRoute(request: HadithRequest(query: request.query))
                            }
                            .accessibilityIdentifier("hadith-search-all")
                        }
                    }
                }
            }
            .id(request)
            .coordinateSpace(name: "hadith-list")
            .task(id: loading) {
                restoringList = true
                guard !loading else { return }
                if let row = restoredRow {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(row, anchor: .top)
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                restoringList = false
            }
        }

        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, offset in
            if !loading {
                listOffset = offset
            }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, !loading, restored, collection == nil, route == nil {
                session?.state.listOffset = listOffset
                saveVisibleRow()
            }
        }
        .onChange(of: visibleRows) { _, _ in saveVisibleRow() }
        .safeAreaInset(edge: .bottom) {
            if showsNarrations, !searchFocused, !history.isEmpty || page.hasMore {
                HStack {
                    Button("Previous") {
                        guard let previous = history.popLast() else { return }
                        listOffset = 0
                        restoredRow = nil
                        visibleRows = [:]
                        session?.state.listRow = nil
                        session?.state.listOffset = 0
                        request.cursor = previous
                    }
                    .disabled(history.isEmpty || loading)
                    .accessibilityIdentifier("hadith-previous-page")
                    Spacer()
                    Button("Next") {
                        guard let next = page.nextCursor else { return }
                        history.append(request.cursor)
                        listOffset = 0
                        restoredRow = nil
                        visibleRows = [:]
                        session?.state.listRow = nil
                        session?.state.listOffset = 0
                        request.cursor = next
                    }
                    .disabled(!page.hasMore || loading)
                    .accessibilityIdentifier("hadith-next-page")
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Hadith")
        .onChange(of: searchText) { _, value in
            guard request.query != value else { return }
            update { $0.query = value; $0.number = nil }
        }
        .searchFocused($searchFocused)
        .onSubmit(of: .search) { searchFocused = false }
        .scrollDismissesKeyboard(.interactively)
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { toolbarActions } label: {
                    Label("Hadith actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("hadith-library-menu")
            }
        }
        .navigationDestination(item: $collection) { book in
            HadithContentsView(book: book, reader: reader, restoredState: collectionRestoration)
        }
        .onChange(of: collection) { old, value in
            if old != nil, value == nil {
                Task { await saveSession(request) }
            }
        }
        .navigationDestination(item: $route) { destination in
            HadithView(reader: reader, initialRequest: destination.request,
                       restoredState: destination.restoresChapter ? restoredState : nil)
                .environment(\.hadithSession, destination.request.collectionID == nil ? nil : session)
        }
        .onChange(of: route) { old, value in
            if old != nil, value == nil {
                Task { await saveSession(request) }
            }
        }
        .navigationDestination(item: $selected) { narration in
            HadithDetailView(initialID: narration.id, reader: reader, query: request.query, orderedFallback: page.usedOrderedFallback)
        }
        .task(id: retry) { await restoreSession() }
        .task(id: LoadRequest(search: request, retry: retry)) {
            if restored {
                await load()
            }
        }
        .onChange(of: selected) { old, value in
            if value == nil, old != nil {
                session?.state.selection = nil; session?.state.detailOffset = 0
            }
        }
        .onDisappear {
            if restored, !loading, collection == nil, route == nil {
                session?.state.listOffset = listOffset
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, restored, !loading, collection == nil, route == nil {
                session?.state.listOffset = listOffset
            }
        }
    }

    @ViewBuilder private var toolbarActions: some View {
        NavigationLink { HadithSavedView(reader: reader) } label: { Label("Highlights", systemImage: "highlighter") }
            .accessibilityIdentifier("hadith-highlights")
        HadithTranslationPicker()
    }

    @ViewBuilder private var chapterResults: some View {
        let groups = HadithContentsGroup.groups(matchingChapters)
        let showBookTitles = request.collectionID == nil || Set(chapters.map(\.bookID)).count > 1
        ForEach(groups) { group in
            Section {
                ForEach(group.chapters) { chapter in
                    Button {
                        searchFocused = false
                        if request.chapterID == chapter.id {
                            searchText = ""
                        } else {
                            if request.collectionID != nil {
                                session?.state.contentsQuery = request.query
                                session?.state.contentsOffset = listOffset
                                session?.state.contentsRow = restoredRow
                            }
                            session?.state.selection = nil
                            session?.state.detailOffset = 0
                            route = SearchRoute(request: HadithRequest(collectionID: chapter.collectionID, chapterID: chapter.id))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chapter.chapterTitle(locale: locale).isEmpty ? chapter.bookTitle(locale: locale) : chapter.chapterTitle(locale: locale))
                            Text("\(chapter.count, format: .number) narrations")
                                .font(.caption).foregroundStyle(.secondary)
                            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                ReadingTimeHint(words: chapter.readingWords)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .listRowBackground(HadithBookStyle.background(for: chapter.collectionID))
                    .accessibilityIdentifier("hadith-chapter-\(chapter.id)")
                    .modifier(HadithListAnchor(id: "chapter:\(chapter.bookID):\(chapter.index)", visibleRows: $visibleRows))
                    .id("chapter:\(chapter.bookID):\(chapter.index)")
                }
            } header: {
                if showBookTitles, let first = group.chapters.first {
                    Text(first.bookTitle(locale: locale)).font(.headline)
                }
            }
        }
    }

    private func saveVisibleRow() {
        guard !loading, !restoringList, restored, collection == nil, route == nil, selected == nil,
              let row = visibleRows.min(by: { $0.value < $1.value })?.key, row != restoredRow else { return }
        restoredRow = row
        session?.state.listRow = row
    }

    private func update(_ change: (inout HadithRequest) -> Void) {
        listOffset = 0
        restoredRow = nil
        visibleRows = [:]
        session?.state.listRow = nil
        session?.state.listOffset = 0
        change(&request)
        request.cursor = HadithCursor()
        history = []
    }

    private func restoreSession() async {
        guard !restored else { return }
        if let initialRequest {
            request = initialRequest
        }
        if initialRequest == nil, let saved = session?.state, let id = saved.request.collectionID {
            do {
                catalog = try await reader.catalog()
                try Task.checkCancellation()
                if let book = catalog.first(where: { $0.id == id }) {
                    collectionRestoration = saved
                    collection = book
                }
            } catch is CancellationError { return }
            catch {
                failed = true
                loading = false
                return
            }
            restored = true
            retry += 1
            return
        }
        var savedState = restoredState ?? (initialRequest == nil ? session?.state : nil)
        if let saved = savedState, initialRequest?.collectionID != nil, initialRequest?.chapterID == nil {
            if saved.request.chapterID != nil {
                request.query = saved.contentsQuery ?? ""
                listOffset = saved.contentsOffset ?? 0
                restoredRow = saved.contentsRow
                route = SearchRoute(request: saved.request, restoresChapter: true)
                savedState = nil
            } else if saved.screen == "contents", saved.request.query.isEmpty {
                request.query = saved.contentsQuery ?? ""
                listOffset = saved.contentsOffset ?? 0
                restoredRow = saved.contentsRow
                savedState = nil
            }
        }
        if let saved = savedState {
            listOffset = saved.listOffset
            restoredRow = saved.listRow
            var restoredRequest = saved.request
            if let number = restoredRequest.number {
                restoredRequest.query = String(number)
                restoredRequest.number = nil
            }
            var restoredHistory = saved.history
            do {
                if let chapter = saved.chapter {
                    restoredRequest.chapterID = try await reader.chapterID(for: chapter)
                }
                let cursors = saved.history + [saved.request.cursor]
                if saved.cursorSources.count == cursors.count {
                    var resolved: [HadithCursor] = []
                    for (cursor, source) in zip(cursors, saved.cursorSources) {
                        if cursor.afterID == 0 {
                            resolved.append(cursor)
                        } else if let source, let id = try await reader.resolve(source) {
                            resolved.append(HadithCursor(phase: cursor.phase, afterID: id))
                        } else {
                            resolved = []; break
                        }
                    }
                    restoredRequest.cursor = resolved.last ?? HadithCursor()
                    restoredHistory = Array(resolved.dropLast())
                } else {
                    restoredRequest.cursor = HadithCursor(); restoredHistory = []
                }
                let books = try await reader.catalog()
                try Task.checkCancellation()
                catalog = books
                if let id = restoredRequest.collectionID, !books.contains(where: { $0.id == id }) {
                    restoredRequest = HadithRequest()
                    restoredHistory = []
                    session?.state.listOffset = 0
                }
                request = restoredRequest
                history = restoredHistory
                if let source = saved.selection, let id = try await reader.resolve(source) {
                    selected = try await reader.detail(id: id).narration
                } else if saved.selection != nil {
                    session?.state.selection = nil
                    session?.state.detailOffset = 0
                }
            } catch is CancellationError {
                return
            } catch {
                // Keep persisted state for a later retry if the asset is temporarily unavailable.
                request.collectionID = saved.request.collectionID
            }
        }
        searchText = request.query
        restored = true
        retry += 1
    }

    private func saveSession(_ current: HadithRequest) async {
        guard let session, collection == nil, route == nil else { return }
        do {
            var sources: [HadithSource?] = []
            for cursor in history + [current.cursor] {
                try await sources.append(cursor.afterID == 0 ? nil : reader.source(id: cursor.afterID))
            }
            let chapter = try await reader.chapterSource(id: current.chapterID)
            guard !Task.isCancelled, current == request, collection == nil, route == nil else { return }
            var state = session.state
            state.screen = "results"
            state.listOffset = listOffset
            state.request = current
            state.listRow = restoredRow
            if current.collectionID != nil, current.chapterID == nil {
                state.contentsQuery = current.query
                state.contentsOffset = listOffset
                state.contentsRow = restoredRow
            }
            state.history = history
            state.cursorSources = sources
            state.chapter = chapter
            session.state = state
        } catch { /* Keep the previous complete session if a query fails. */ }
    }

    private func narrationResults(_ narrations: [Hadith], orderedFallback: Bool = false) -> some View {
        Section {
            if orderedFallback, !narrations.isEmpty {
                Text("No exact phrase found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hadith-ordered-fallback")
            }
            ForEach(narrations) { narration in
                Button { searchFocused = false; selected = narration } label: {
                    HadithPreviewRow(narration: narration, showsReadingTime: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
                .listRowBackground(HadithBookStyle.background(for: narration.collectionID))
                .contextMenu {
                    Button("Open", systemImage: "arrow.up.forward") {
                        searchFocused = false
                        selected = narration
                    }
                } preview: {
                    HadithPeekView(id: narration.id, reader: reader)
                }
                .accessibilityIdentifier("hadith-result-\(narration.id)")
                .modifier(HadithListAnchor(id: "hadith:" + (narration.source?.key ?? String(narration.id)), visibleRows: $visibleRows))
                .id("hadith:" + (narration.source?.key ?? String(narration.id)))
            }
        } header: {
            HStack {
                Text("Hadith")
                Spacer()
                if query.isEmpty, let chapter = chapters.first(where: { $0.id == request.chapterID }) {
                    ReadingTimeHint(words: chapter.readingWords)
                }
            }
        }
    }

    private func load() async {
        let current = request
        loading = true
        failed = false
        page = HadithPage(rows: [], hasMore: false)
        do {
            if catalog.isEmpty {
                let books = try await reader.catalog()
                try Task.checkCancellation()
                guard current == request else { return }
                catalog = books
            }
            if current.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let collectionID = current.collectionID {
                introductions = try await reader.introductions(collectionID: collectionID, chapterID: current.chapterID)
            } else {
                introductions = []
            }
            if chapters.isEmpty, current.collectionID != nil || !query.isEmpty {
                let values = try await reader.chapters(collectionID: current.collectionID)
                try Task.checkCancellation()
                guard current == request else { return }
                chapters = values
            }
            if showsNarrations {
                if !current.query.isEmpty {
                    try await Task.sleep(for: .milliseconds(250))
                }
                var search = current
                if let number = HadithSearch.number(current.query) {
                    search.number = number
                    search.query = ""
                }
                let result = try await reader.page(search)
                try Task.checkCancellation()
                guard current == request else { return }
                page = result
            }
            try Task.checkCancellation()
            guard current == request else { return }
            await saveSession(current)
            guard !Task.isCancelled else { return }
            completedRequest = current
            loading = false
        } catch is CancellationError {
            // The replacement request owns the UI state.
        } catch {
            guard !Task.isCancelled, current == request else { return }
            assets?.invalidateValidation()
            failed = true
            loading = false
        }
    }
}

struct HadithLoadError: View {
    var supplications = false
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(supplications ? "Unable to load supplications" : "Unable to load Hadith"), systemImage: "exclamationmark.triangle")
        } description: {
            Text("Please try again.")
        } actions: {
            Button("Try again", action: retry)
        }
    }
}

struct HadithSavedView: View {
    @Environment(\.hadithAssets) private var assets
    let reader: HadithReader
    var supplications = false
    @Environment(\.quranUserStore) private var store
    @State private var rows: [String: Int] = [:]
    @State private var availableHighlights: Set<String> = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var editing: ReadingHighlight?

    private var highlights: [ReadingHighlight] {
        store?.highlights.filter {
            $0.isHadith && (HadithSource(key: $0.source)?.book == Hadith.supplicationCollectionID) == supplications
        } ?? []
    }

    private var keys: [String] {
        Array(Set(highlights.map(\.source))).sorted()
    }

    var body: some View {
        List {
            if store?.unavailable != false {
                ContentUnavailableView {
                    Label("Highlights unavailable", systemImage: "exclamationmark.triangle")
                } actions: { Button("Try again") { store?.reopen() } }
            } else if loading {
                ProgressView()
            } else if failed {
                HadithLoadError(supplications: supplications) { Task { await assets?.refresh(); retry += 1 } }
            } else if highlights.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter")
            } else {
                ForEach(highlights) { highlight in
                    Group {
                        if let id = rows[highlight.source] {
                            NavigationLink {
                                HadithDetailView(initialID: id, reader: reader, query: "", orderedFallback: false, highlight: highlight, supplication: supplications)
                            } label: { HighlightSummary(highlight: highlight, available: availableHighlights.contains(highlight.id)) }
                                .accessibilityIdentifier("saved-hadith-\(highlight.source)")
                        } else {
                            Button { editing = highlight } label: {
                                HighlightSummary(highlight: highlight, available: false)
                            }
                            .tint(.primary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit highlight", systemImage: "pencil") { editing = highlight }
                            .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Edit highlight", systemImage: "pencil") { editing = highlight }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Highlights")
        .sheet(item: $editing) { HighlightEditor(highlight: $0, existing: true) }
        .task(id: highlights.map { $0.id + String($0.modifiedAt.timeIntervalSince1970) }.joined(separator: "|") + "-\(retry)") {
            loading = true
            failed = false
            do {
                var loaded: [String: Int] = [:]
                var available: Set<String> = []
                for key in keys {
                    guard let source = HadithSource(key: key), let id = try await reader.resolve(source) else { continue }
                    let narration = try await reader.detail(id: id).narration
                    loaded[key] = id
                    let blocks = narration.highlightBlocks
                    for highlight in highlights where highlight.source == key && highlight.isAvailable(in: blocks) {
                        available.insert(highlight.id)
                    }
                    try Task.checkCancellation()
                }
                rows = loaded
                availableHighlights = available
                loading = false
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    assets?.invalidateValidation()
                    loading = false; failed = true
                }
            }
        }
    }
}

extension Hadith {
    var highlightBlocks: [String: String] {
        ["arabic": HighlightTextContent.canonical(arabicDisplay),
         "english": HighlightTextContent.canonical(englishDisplay),
         "englishNarrator": HighlightTextContent.canonical(narratorDisplay)]
    }
}
