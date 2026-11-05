import SwiftUI

struct QuranChapterView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var textSizePresented = false
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    @Environment(\.locale) private var locale
    @State private var translationStore = QuranTranslationStore.shared
    @State private var verses: [Ayah] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var jumpPresented = false
    @State private var verseNumber = ""
    @State private var invalidVerse = false
    @State private var target: Int?
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
                    ForEach(verses) { ayah in
                        QuranVerseRow(ayah: ayah, translation: QuranTranslation.catalog.first { $0.id == translationStore.activeID })
                            .id(ayah.number)
                            .accessibilityIdentifier("quran-verse-\(ayah.id)")
                    }
                }
            }
            .task(id: verses.count) {
                guard !verses.isEmpty else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(initialVerse, anchor: .top)
                await Task.yield()
                focusReady = true
            }
            .onChange(of: target) { _, number in
                if let number {
                    proxy.scrollTo(number, anchor: .top)
                }
                target = nil
            }
        }
        .environment(\.focusedHighlight, focusReady ? highlight : nil)
        .navigationTitle(surah.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Go to verse", systemImage: "number") { jumpPresented = true }
                    .disabled(verses.isEmpty)
                    .accessibilityIdentifier("quran-jump")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    QuranTranslationPicker()
                    ReadingSizeMenu(isPresented: $textSizePresented)
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }.accessibilityIdentifier("quran-reading-options")
                    .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
            }
        }
        .alert("Go to verse", isPresented: $jumpPresented) {
            TextField("Verse number", text: $verseNumber).keyboardType(.numberPad)
            Button("Go") {
                if let number = QuranSearchText.number(verseNumber), verses.contains(where: { $0.number == number }) {
                    target = number
                } else {
                    invalidVerse = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a verse from \(1, format: .number) to \(verses.count, format: .number).")
        }
        .alert("Invalid verse reference", isPresented: $invalidVerse) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter a verse from \(1, format: .number) to \(verses.count, format: .number).")
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
