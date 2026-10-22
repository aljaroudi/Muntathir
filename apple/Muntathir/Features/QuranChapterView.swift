import SwiftUI

struct QuranChapterView: View {
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    let translations: [QuranTranslation]
    @Binding var translationID: String
    @Environment(\.locale) private var locale
    @State private var verses: [Ayah] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var jumpPresented = false
    @State private var verseNumber = ""
    @State private var invalidVerse = false
    @State private var target: Int?

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
                        QuranVerseRow(ayah: ayah, translation: translations.first { $0.id == translationID })
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
            }
            .onChange(of: target) { _, number in
                if let number {
                    proxy.scrollTo(number, anchor: .top)
                }
                target = nil
            }
        }
        .navigationTitle(surah.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Go to verse", systemImage: "number") { jumpPresented = true }
                    .disabled(verses.isEmpty)
                    .accessibilityIdentifier("quran-jump")
            }
            ToolbarItem(placement: .topBarTrailing) {
                QuranTranslationPicker(translations: translations, selection: $translationID)
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
            Text("Enter a verse from 1 to \(verses.count).")
        }
        .alert("Invalid verse reference", isPresented: $invalidVerse) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter a verse from 1 to \(verses.count).")
        }
        .task(id: retry) {
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
