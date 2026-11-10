import SwiftUI

struct QuranChapterView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var textSizePresented = false
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    var positionChanged: (Int, Int) -> Void = { _, _ in }
    @State private var visibleVerses: Set<Int> = []
    @Environment(\.locale) private var locale
    @State private var translationStore = QuranTranslationStore.shared
    @State private var readingWords = 0
    @State private var verses: [Ayah] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var activatedHighlight = false
    @State private var focusReady = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if loading {
                    ProgressView("Loading Quran…").frame(maxWidth: .infinity)
                } else if failed {
                    ContentUnavailableView {
                        Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Please try again.")
                    } actions: {
                        Button("Try again") { retry += 1 }
                    }
                } else {
                    Section {
                        ForEach(verses) { ayah in
                            QuranVerseRow(ayah: ayah, translation: QuranTranslation.catalog.first { $0.id == translationStore.activeID })
                                .onGeometryChange(for: Bool.self) { geometry in
                                    let frame = geometry.frame(in: .scrollView)
                                    return frame.maxY > 0 && frame.minY < (geometry.bounds(of: .scrollView)?.height ?? 0)
                                } action: { visible in
                                    if visible {
                                        visibleVerses.insert(ayah.number)
                                    } else {
                                        visibleVerses.remove(ayah.number)
                                    }
                                    if let first = visibleVerses.min() {
                                        positionChanged(surah.id, first)
                                    }
                                }
                                .id(ayah.number)
                                .accessibilityIdentifier("quran-verse-\(ayah.id)")
                        }
                    } header: {
                        ReadingTimeHint(words: readingWords)
                    }
                }
            }
            .task(id: verses.count) {
                guard !verses.isEmpty else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if initialVerse != 1 {
                    proxy.scrollTo(initialVerse, anchor: .top)
                }
                await Task.yield()
                focusReady = true
            }
        }
        .environment(\.focusedHighlight, focusReady ? highlight : nil)
        .navigationTitle(surah.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    QuranReadingModePicker()
                    QuranTranslationPicker()
                    ReadingSizeMenu(isPresented: $textSizePresented)
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }.accessibilityIdentifier("quran-reading-options")
                    .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
            }
        }
        .task(id: "\(retry)-\(translationStore.revision)") {
            if !activatedHighlight {
                activatedHighlight = true
                if let block = highlight?.block, block != "arabic", translationStore.activeID != block {
                    translationStore.select(block)
                }
            }
            loading = true
            failed = false
            do {
                let loaded = try await reader.verses(surah: surah.id)
                try Task.checkCancellation()
                readingWords = loaded.reduce(0) { $0 + ReadingTime.words(arabic: $1.text) }
                verses = loaded
                failed = loaded.isEmpty
                loading = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                loading = false
            }
        }
    }
}
