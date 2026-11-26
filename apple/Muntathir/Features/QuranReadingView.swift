import SwiftUI

struct QuranReadingView: View {
    @State private var submittedQuery = ""
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    var searchQuery = ""
    @AppStorage("quranReadingMode") private var mode: QuranReadingMode = .verses
    @State private var position: (surah: Int, verse: Int)?
    @State private var query = ""
    @State private var searchPresented = false
    @FocusState private var searchFocused: Bool
    @State private var searchSurah: QuranSurah?
    @State private var surahs: [QuranSurah] = []
    @Environment(\.splitState) private var splitState

    /// On macOS a split view puts every column's search field in the one window toolbar, and AppKit
    /// aborts on a second one, so beside the surah list only the list searches.
    private var hasOwnSearch: Bool {
        #if os(macOS)
            splitState == nil
        #else
            true
        #endif
    }

    private var showingResults: Bool {
        !submittedQuery.isEmpty
    }

    private var currentSurah: QuranSurah {
        guard let position, position.surah != surah.id else { return surah }
        return surahs.first { $0.id == position.surah } ?? surah
    }

    var body: some View {
        ZStack {
            readingContent
                .ignoresSafeArea(.keyboard, edges: mode == .mushaf ? .bottom : [])
                .opacity(showingResults ? 0 : 1)
                .allowsHitTesting(!showingResults)
                .accessibilityHidden(showingResults)
            if showingResults {
                QuranSearchContent(submittedQuery: submittedQuery, reader: reader, surah: searchSurah ?? currentSurah)
            }
        }
        .environment(\.searchMatchQuery, searchQuery)
        .readingBackground()
        .readingSearchable(hasOwnSearch, text: $query, isPresented: $searchPresented)
        .searchHistory($query, area: .quran)
        .submitsSearch($query, submitted: $submittedQuery)
        .onSubmit(of: .search) { searchFocused = false }
        .searchFocused($searchFocused)
        .autocorrectionDisabled()
        .task {
            guard surahs.isEmpty else { return }
            surahs = (try? QuranSurah.load()) ?? []
        }
        .onChange(of: searchPresented) { _, presented in
            if presented {
                searchSurah = currentSurah
            } else {
                searchFocused = false
                query = ""
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

private extension View {
    @ViewBuilder func readingSearchable(_ enabled: Bool, text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        if enabled {
            searchable(text: text, isPresented: isPresented, placement: .alwaysVisible, prompt: "Verse number or Quran text")
        } else {
            self
        }
    }
}
