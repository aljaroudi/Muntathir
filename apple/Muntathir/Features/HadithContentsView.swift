import SwiftUI

struct HadithContentsView: View {
    let book: HadithCollection
    let reader: HadithReader
    var restoredState: HadithSessionState?
    @Environment(\.locale) private var locale
    @Environment(\.hadithSession) private var session
    @Environment(\.hadithAssets) private var assets
    @State private var chapters: [HadithChapter] = []
    @State private var query = ""
    @State private var position = ScrollPosition()
    @State private var offset: Double = 0
    @State private var loading = true
    @State private var failed = false
    @State private var restored = false
    @State private var retry = 0
    @State private var destination: Destination?
    @State private var resultRestoration: HadithSessionState?
    @State private var jumpPresented = false
    @State private var jumpText = ""
    @State private var invalidNumber = false

    private struct Destination: Hashable, Identifiable {
        let id = UUID()
        let request: HadithRequest
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if loading {
                    ProgressView("Loading Hadith…").frame(maxWidth: .infinity)
                } else if failed {
                    HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
                } else {
                    let groups = HadithContentsGroup.groups(chapters, matching: query)
                    let showBookTitles = Set(chapters.map(\.bookID)).count > 1
                    if groups.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.chapters) { chapter in
                                Button {
                                    open(HadithRequest(collectionID: book.id, chapterID: chapter.id))
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(chapter.chapterTitle(locale: locale).isEmpty ? chapter.bookTitle(locale: locale) : chapter.chapterTitle(locale: locale))
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text("\(chapter.count, format: .number) narrations")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.forward")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(HadithBookStyle.background(for: book.id), in: .rect(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("hadith-chapter-\(chapter.id)")
                            }
                        } header: {
                            if showBookTitles, let first = group.chapters.first {
                                Text(first.bookTitle(locale: locale))
                                    .font(.headline).padding(.top, 8)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: {
            _, value in if !loading {
                offset = value
            }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle {
                saveContents()
            }
        }
        .navigationTitle(book.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search contents")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, _ in saveContents() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search narrations", systemImage: "text.magnifyingglass") {
                    open(HadithRequest(collectionID: book.id))
                }
                .accessibilityIdentifier("hadith-search-narrations")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Go to hadith", systemImage: "number") { jumpPresented = true }
                    .accessibilityIdentifier("hadith-jump")
            }
        }
        .navigationDestination(item: $destination) { value in
            HadithView(reader: reader, initialRequest: value.request, restoredState: resultRestoration)
        }
        .onChange(of: destination) { old, value in
            if old != nil, value == nil {
                saveContents()
            }
        }
        .alert("Go to hadith", isPresented: $jumpPresented) {
            TextField("Hadith number", text: $jumpText).keyboardType(.numberPad)
            Button("Go") {
                if let number = QuranSearchText.number(jumpText), number > 0 {
                    open(HadithRequest(collectionID: book.id, number: number))
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
        .task(id: retry) { await load() }
    }

    private func open(_ request: HadithRequest) {
        saveContents()
        resultRestoration = nil
        session?.state.selection = nil
        session?.state.detailOffset = 0
        session?.state.listOffset = 0
        destination = Destination(request: request)
    }

    private func saveContents() {
        guard restored, !loading, destination == nil, let session else { return }
        var state = session.state
        state.screen = "contents"
        state.request = HadithRequest(collectionID: book.id)
        state.contentsQuery = query
        state.contentsOffset = offset
        state.selection = nil
        state.chapter = nil
        state.history = []
        state.cursorSources = []
        state.listOffset = 0
        state.detailOffset = 0
        session.state = state
    }

    private func load() async {
        loading = true
        failed = false
        do {
            chapters = try await reader.chapters(collectionID: book.id)
            try Task.checkCancellation()
            if !restored {
                query = restoredState?.contentsQuery ?? ""
                offset = restoredState?.contentsOffset ?? 0
                if let saved = restoredState, saved.screen != "contents" {
                    resultRestoration = saved
                    destination = Destination(request: saved.request)
                }
                restored = true
            }
            loading = false
            position.scrollTo(y: offset)
            saveContents()
        } catch is CancellationError {
        } catch {
            failed = true
            loading = false
        }
    }
}
