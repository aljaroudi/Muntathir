import SwiftUI

struct HadithView: View {
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
        ScrollViewReader { proxy in
            List {
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
                                    .listRowBackground(HadithBookStyle.background(for: book.id))
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
                            .listRowBackground(HadithBookStyle.background(for: narration.collectionID))
                            .accessibilityIdentifier("hadith-result-\(narration.id)")
                        }
                    }
                }
                if loading {
                    ProgressView("Loading Hadith…").frame(maxWidth: .infinity)
                } else if failed {
                    HadithLoadError { retry += 1 }
                } else if !browsingCatalog, page.rows.isEmpty {
                    ContentUnavailableView.search(text: request.number.map(String.init) ?? request.query)
                }
            }
            .onChange(of: page.rows.first?.id) { proxy.scrollTo("top", anchor: .top) }
        }
        .safeAreaInset(edge: .bottom) {
            if !browsingCatalog, !searchFocused, !history.isEmpty || page.hasMore {
                HStack {
                    Button("Previous") {
                        guard let previous = history.popLast() else { return }
                        request.cursor = previous
                    }
                    .disabled(history.isEmpty || loading)
                    .accessibilityIdentifier("hadith-previous-page")
                    Spacer()
                    Button("Next") {
                        guard let next = page.nextCursor else { return }
                        history.append(request.cursor)
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
            if let removeDownload {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove download", systemImage: "trash", action: removeDownload)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { HadithTranslationPicker() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Go to hadith", systemImage: "number") { jumpPresented = true }
                    .disabled(request.collectionID == nil)
                    .accessibilityIdentifier("hadith-jump")
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
        .task(id: LoadRequest(search: request, retry: retry)) { await load() }
    }

    private func update(_ change: (inout HadithRequest) -> Void) {
        openSingleMatch = false
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
            loading = false
        } catch is CancellationError {
            // The replacement request owns the UI state.
        } catch {
            guard !Task.isCancelled, current == request else { return }
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
