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
    var removeDownload: (() -> Void)?
    @State private var catalog: [HadithCollection] = []
    @State private var chapters: [HadithChapter] = []
    @State private var request = HadithRequest()
    @State private var page = HadithPage(rows: [], hasMore: false)
    @State private var history: [HadithCursor] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var filter: Filter?
    @State private var jumpPresented = false
    @State private var jumpText = ""
    @State private var invalidNumber = false
    @State private var selected: Hadith?
    @State private var openSingleMatch = false

    private enum Filter: String, Identifiable {
        case books, chapters
        var id: String {
            rawValue
        }
    }

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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Section {
                    Button { filter = .books } label: {
                        LabeledContent("Book", value: selectedBook?.title(locale: locale) ?? String(localized: "All books"))
                    }
                    .accessibilityIdentifier("hadith-book-filter")
                    if request.collectionID != nil {
                        Button { filter = .chapters } label: {
                            LabeledContent("Chapter", value: chapters.first { $0.id == request.chapterID }?.title(locale: locale) ?? String(localized: "All chapters"))
                        }
                        .accessibilityIdentifier("hadith-chapter-filter")
                    }
                    if request.number != nil {
                        Button("Clear number filter") { update { $0.number = nil } }
                    }
                }
                .id("top")
                if request.collectionID == nil, request.number == nil, !matchingBooks.isEmpty {
                    ForEach(HadithBookGroup.allCases) { group in
                        let books = matchingBooks.filter { $0.group == group }.sorted {
                            $0.title(locale: locale).compare($1.title(locale: locale), options: .numeric, locale: locale) == .orderedAscending
                        }
                        if !books.isEmpty {
                            Section(LocalizedStringKey(group.rawValue)) {
                                ForEach(books) { book in
                                    Button { chooseBook(book.id, clearQuery: true) } label: {
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
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, offset in
            listOffset = offset
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, !loading, restored {
                session?.state.listOffset = listOffset
            }
        }
        .onChange(of: loading) { _, loading in
            if !loading {
                scrollPosition.scrollTo(y: session?.state.listOffset ?? 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !browsingCatalog, !searchFocused, !history.isEmpty || page.hasMore {
                HStack {
                    Button("Previous") {
                        guard let previous = history.popLast() else { return }
                        session?.state.listOffset = 0
                        request.cursor = previous
                    }
                    .disabled(history.isEmpty || loading)
                    .accessibilityIdentifier("hadith-previous-page")
                    Spacer()
                    Button("Next") {
                        guard let next = page.nextCursor else { return }
                        history.append(request.cursor)
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
        .navigationTitle(selectedBook?.title(locale: locale) ?? String(localized: "Hadith"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: Binding(get: { request.query }, set: { value in
            update { $0.query = value; $0.number = nil }
        }), placement: .navigationBarDrawer(displayMode: .always), prompt: "Book or narration text")
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
        .sheet(item: $filter) { kind in
            HadithFilterView(books: kind == .books ? catalog : nil, chapters: chapters) { bookID, chapterID in
                if kind == .books {
                    chooseBook(bookID)
                } else {
                    update { $0.chapterID = chapterID }
                }
                filter = nil
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
        .task { await restoreSession() }
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
            if restored, !loading {
                session?.state.listOffset = listOffset
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, restored, !loading {
                session?.state.listOffset = listOffset
            }
        }
    }

    @ViewBuilder private var toolbarActions: some View {
        NavigationLink { HadithSavedView(notes: false, reader: reader) } label: { Label("Bookmarks", systemImage: "bookmark") }
            .accessibilityIdentifier("hadith-favorites")
        NavigationLink { HadithSavedView(notes: true, reader: reader) } label: { Label("Notes", systemImage: "note.text") }
            .accessibilityIdentifier("hadith-notes")
        HadithTranslationPicker()
        Button("Go to hadith", systemImage: "number") { jumpPresented = true }
            .disabled(request.collectionID == nil)
            .accessibilityIdentifier("hadith-jump")
        #if DEBUG
            if let removeDownload {
                Menu {
                    Button("Remove download", systemImage: "trash", role: .destructive, action: removeDownload)
                } label: { Label { Text(verbatim: "Debug") } icon: { Image(systemName: "ladybug") } }
            }
        #endif
    }

    private func update(_ change: (inout HadithRequest) -> Void) {
        openSingleMatch = false
        session?.state.listOffset = 0
        change(&request)
        request.cursor = HadithCursor()
        history = []
    }

    private func chooseBook(_ id: String?, clearQuery: Bool = false) {
        chapters = []
        update {
            $0.collectionID = id
            $0.chapterID = nil
            $0.number = nil
            if clearQuery {
                $0.query = ""
            }
        }
    }

    private func restoreSession() async {
        guard !restored else { return }
        if let saved = session?.state {
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
        restored = true
        retry += 1
    }

    private func saveSession(_ current: HadithRequest) async {
        guard let session else { return }
        do {
            var sources: [HadithSource?] = []
            for cursor in history + [current.cursor] {
                try await sources.append(cursor.afterID == 0 ? nil : reader.source(id: cursor.afterID))
            }
            let chapter = try await reader.chapterSource(id: current.chapterID)
            guard !Task.isCancelled, current == request else { return }
            var state = session.state
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
    let notes: Bool
    let reader: HadithReader
    @Environment(\.quranUserStore) private var store
    @Environment(\.locale) private var locale
    @State private var rows: [String: Hadith] = [:]
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    private var keys: [String] {
        (store?.hadithStates.values.filter { notes ? !$0.note.isEmpty : $0.isFavorite }.map(\.id) ?? []).sorted()
    }

    var body: some View {
        List {
            if store?.unavailable != false {
                ContentUnavailableView {
                    Label("Bookmarks and notes unavailable", systemImage: "exclamationmark.triangle")
                } actions: { Button("Try again") { store?.reopen() } }
            } else if loading {
                ProgressView("Loading Hadith…")
            } else if failed {
                HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
            } else if keys.isEmpty {
                ContentUnavailableView(notes ? "No notes yet" : "No bookmarks yet", systemImage: notes ? "note.text" : "bookmark")
            } else {
                ForEach(keys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 12) {
                        if let narration = rows[key] {
                            NavigationLink {
                                HadithDetailView(initialID: narration.id, reader: reader, query: "", orderedFallback: false)
                            } label: { HadithPreviewRow(narration: narration) }
                        } else {
                            Label("This narration is unavailable in the installed library.", systemImage: "book.closed")
                            if let source = HadithSource(key: key) {
                                Text("\(source.book) · \(source.number)").font(.caption)
                            }
                        }
                        if notes, let note = store?.hadithState(for: key).note {
                            Text(note).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(notes ? Text("Notes") : Text("Bookmarks"))
        .task(id: keys.joined(separator: "|") + "-\(retry)") {
            loading = true
            failed = false
            do {
                var loaded: [String: Hadith] = [:]
                for key in keys {
                    guard let source = HadithSource(key: key), let id = try await reader.resolve(source) else { continue }
                    let detail = try await reader.detail(id: id)
                    let n = detail.narration
                    loaded[key] = Hadith(id: id, collectionID: n.collectionID, number: n.number, chapter: n.chapter,
                                         arabic: String(HadithText.preview(n.arabic, terms: []).characters), englishNarrator: "", english: String(HadithText.preview(n.english, terms: []).characters), source: n.source,
                                         arabicDisplay: HadithText.preview(n.arabic, terms: []), englishDisplay: HadithText.preview(n.english, terms: []))
                    try Task.checkCancellation()
                }
                rows = loaded
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
