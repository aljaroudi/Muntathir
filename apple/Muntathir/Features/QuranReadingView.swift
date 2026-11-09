import SwiftUI

struct QuranReadingView: View {
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    @AppStorage("quranReadingMode") private var mode: QuranReadingMode = .verses
    @State private var position: (surah: Int, verse: Int)?
    @State private var query = ""
    @State private var searchPresented = false
    @State private var searchSurah: QuranSurah?
    @State private var surahs: [QuranSurah] = []

    private var showingResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSurah: QuranSurah {
        guard let position, position.surah != surah.id else { return surah }
        return surahs.first { $0.id == position.surah } ?? surah
    }

    var body: some View {
        ZStack {
            readingContent
                .opacity(showingResults ? 0 : 1)
                .allowsHitTesting(!showingResults)
                .accessibilityHidden(showingResults)
            if showingResults {
                QuranSearchContent(query: $query, reader: reader, surah: searchSurah ?? currentSurah)
            }
        }
        .searchable(text: $query, isPresented: $searchPresented,
                    placement: .toolbar, prompt: "Verse number or Quran text")
        .searchToolbarBehavior(.minimize)
        .autocorrectionDisabled()
        .task {
            guard surahs.isEmpty else { return }
            surahs = (try? QuranSurah.load()) ?? []
        }
        .onChange(of: searchPresented) { _, presented in
            if presented {
                searchSurah = currentSurah
            } else if query.isEmpty {
                searchSurah = nil
            }
        }
    }

    @ViewBuilder private var readingContent: some View {
        if mode == .mushaf {
            QuranMushafView(surah: currentSurah, initialVerse: position?.verse ?? initialVerse,
                            reader: reader, highlight: highlight, positionChanged: updatePosition)
        } else {
            QuranChapterView(surah: currentSurah, initialVerse: position?.verse ?? initialVerse,
                             reader: reader, highlight: highlight, positionChanged: updatePosition)
        }
    }

    private func updatePosition(_ surah: Int, _ verse: Int) {
        guard !showingResults else { return }
        guard position?.surah != surah || position?.verse != verse else { return }
        position = (surah, verse)
    }
}
