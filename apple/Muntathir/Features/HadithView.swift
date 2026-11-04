import SwiftUI

struct HadithView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hadithAssets) private var assets
    @Environment(\.hadithSession) private var session
    @State private var restored = false
    @State private var scrollPosition = ScrollPosition()
    @State private var listOffset: Double = 0
    @Environment(\.locale) private var locale
    @FocusState private var searchFocused: Bool
    let reader: HadithReader
    var initialRequest: HadithRequest?
    var restoredState: HadithSessionState?
    @State private var collection: HadithCollection?
    @State private var collectionRestoration: HadithSessionState?
    @State private var catalog: [HadithCollection] = []
    @State private var chapters: [HadithChapter] = []
    @State private var request = HadithRequest()
    @State private var page = HadithPage(rows: [], hasMore: false)
    @State private var history: [HadithCursor] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var jumpPresented = false
    @State private var jumpText = ""
    @State private var invalidNumber = false
    @State private var selected: Hadith?
    @State private var openSingleMatch = false

    private struct LoadRequest: Equatable {
        let search: HadithRequest
        let retry: Int
    }

    private var browsingCatalog: Bool {
        request.collectionID == nil && request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && request.number == nil
    }

    private var matchingBooks: [HadithCollection] {
        catalog.filter { request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.matches(request.query) }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if request.number != nil {
                    Button("Clear number filter") { update { $0.number = nil } }
                }
                if request.collectionID == nil, request.number == nil, !matchingBooks.isEmpty {
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
                                    }
                                    .accessibilityIdentifier("hadith-book-\(book.id)")
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(HadithBookStyle.background(for: book.id), in: .rect(cornerRadius: 14))
                                }
                            }
                        }
                    }
                }
                if !browsingCatalog {
                    Section("Hadith") {
                        if page.usedOrderedFallback, !page.rows.isEmpty {
                            Text("No exact phrase found.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("hadith-ordered-fallback")
                        }
                        ForEach(page.rows) { narration in
                            Button { searchFocused = false; selected = narration } label: {
                                HadithPreviewRow(narration: narration)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .background(HadithBookStyle.background(for: narration.collectionID), in: .rect(cornerRadius: 14))
                            .accessibilityIdentifier("hadith-result-\(narration.id)")
                        }
                    }
                }
                if loading {
                    ProgressView("Loading Hadith…").frame(maxWidth: .infinity)
                } else if failed {
                    HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
                } else if !browsingCatalog, page.rows.isEmpty {
                    ContentUnavailableView.search(text: request.number.map(String.init) ?? request.query)
                        .accessibilityIdentifier("hadith-empty-results")
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, offset in
            if !loading {
                listOffset = offset
            }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, !loading, restored, collection == nil {
                session?.state.listOffset = listOffset
            }
        }
        .onChange(of: loading) { _, loading in
            if !loading {
                scrollPosition.scrollTo(y: listOffset)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !browsingCatalog, !searchFocused, !history.isEmpty || page.hasMore {
                HStack {
                    Button("Previous") {
                        guard let previous = history.popLast() else { return }
                        listOffset = 0
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
        .searchable(text: Binding(get: { request.query }, set: { value in
            update { $0.query = value; $0.number = nil }
        }), placement: .navigationBarDrawer(displayMode: .always), prompt: initialRequest == nil ? "Book or narration text" : "Search narrations")
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
        .alert("Go to hadith", isPresented: $jumpPresented) {
            TextField("Hadith number", text: $jumpText).keyboardType(.numberPad)
            Button("Go") {
                if let number = QuranSearchText.number(jumpText), number > 0 {
                    update { $0.number = number; $0.query = "" }
                    openSingleMatch = true
                    retry += 1
                } else {
                    invalidNumber = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Numbers may repeat across chapters. Choose a matching reference.")
        }
        .alert("Invalid hadith number", isPresented: $invalidNumber) {
            Button("OK", role: .cancel) {}
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
            if restored, !loading, collection == nil {
                session?.state.listOffset = listOffset
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, restored, !loading, collection == nil {
                session?.state.listOffset = listOffset
            }
        }
    }

    @ViewBuilder private var toolbarActions: some View {
        NavigationLink { HadithSavedView(reader: reader) } label: { Label("Highlights", systemImage: "highlighter") }
            .accessibilityIdentifier("hadith-highlights")
        HadithTranslationPicker()
        Button("Go to hadith", systemImage: "number") { jumpPresented = true }
            .disabled(request.collectionID == nil)
            .accessibilityIdentifier("hadith-jump")
    }

    private func update(_ change: (inout HadithRequest) -> Void) {
        openSingleMatch = false
        listOffset = 0
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
        if let saved = restoredState ?? (initialRequest == nil ? session?.state : nil) {
            listOffset = saved.listOffset
            var restoredRequest = saved.request
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
        if initialRequest?.number != nil, restoredState == nil {
            openSingleMatch = true
        }
        restored = true
        retry += 1
    }

    private func saveSession(_ current: HadithRequest) async {
        guard let session, collection == nil else { return }
        do {
            var sources: [HadithSource?] = []
            for cursor in history + [current.cursor] {
                try await sources.append(cursor.afterID == 0 ? nil : reader.source(id: cursor.afterID))
            }
            let chapter = try await reader.chapterSource(id: current.chapterID)
            guard !Task.isCancelled, current == request, collection == nil else { return }
            var state = session.state
            state.screen = "results"
            state.listOffset = listOffset
            state.request = current
            state.history = history
            state.cursorSources = sources
            state.chapter = chapter
            session.state = state
        } catch { /* Keep the previous complete session if a query fails. */ }
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
            if let id = current.collectionID, chapters.isEmpty {
                let values = try await reader.chapters(collectionID: id)
                try Task.checkCancellation()
                guard current == request else { return }
                chapters = values
            }
            if !browsingCatalog {
                if !current.query.isEmpty {
                    try await Task.sleep(for: .milliseconds(250))
                }
                let result = try await reader.page(current)
                try Task.checkCancellation()
                guard current == request else { return }
                page = result
                if openSingleMatch, current.number != nil, current.cursor == HadithCursor(), result.rows.count == 1, !result.hasMore {
                    openSingleMatch = false
                    selected = result.rows[0]
                }
            }
            try Task.checkCancellation()
            guard current == request else { return }
            await saveSession(current)
            guard !Task.isCancelled else { return }
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
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Unable to load Hadith", systemImage: "exclamationmark.triangle")
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
    @Environment(\.quranUserStore) private var store
    @State private var rows: [String: Int] = [:]
    @State private var availableHighlights: Set<String> = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var editing: ReadingHighlight?

    private var highlights: [ReadingHighlight] {
        store?.highlights.filter(\.isHadith) ?? []
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
                ProgressView("Loading Hadith…")
            } else if failed {
                HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
            } else if highlights.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter")
            } else {
                ForEach(highlights) { highlight in
                    Group {
                        if let id = rows[highlight.source] {
                            NavigationLink {
                                HadithDetailView(initialID: id, reader: reader, query: "", orderedFallback: false, highlight: highlight)
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
