import SwiftUI

struct QuranReadingView: View {
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    @AppStorage("quranReadingMode") private var mode: QuranReadingMode = .verses
    @State private var position: (surah: Int, verse: Int)?
    private var currentSurah: QuranSurah {
        guard let position, position.surah != surah.id else { return surah }
        return (try? QuranSurah.load().first { $0.id == position.surah }) ?? surah
    }

    var body: some View {
        if mode == .mushaf {
            QuranMushafView(surah: currentSurah, initialVerse: position?.verse ?? initialVerse,
                            reader: reader, highlight: highlight, positionChanged: updatePosition)
        } else {
            QuranChapterView(surah: currentSurah, initialVerse: position?.verse ?? initialVerse,
                             reader: reader, highlight: highlight, positionChanged: updatePosition)
        }
    }

    private func updatePosition(_ surah: Int, _ verse: Int) {
        position = (surah, verse)
    }
}
