import SwiftUI

struct QuranReadingModePicker: View {
    @AppStorage("quranReadingMode") private var mode: QuranReadingMode = .verses

    var body: some View {
        Picker("Reading mode", selection: $mode) {
            Text("Verses").tag(QuranReadingMode.verses)
            Text("Mushaf").tag(QuranReadingMode.mushaf)
        }
        .accessibilityIdentifier("quran-reading-mode")
    }
}
