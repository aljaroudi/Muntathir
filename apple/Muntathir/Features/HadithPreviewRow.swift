import SwiftUI

struct HadithPreviewRow: View {
    let narration: Hadith
    var searching = false
    @AppStorage("hadithEnglishEnabled.v2") private var showEnglish = SupplicationTranslation.prefersEnglish()
    @Environment(\.locale) private var locale

    // Displays arrive as reader-prepared previews, so rendering never trims or searches text again.
    var body: some View {
        let blocks = [narration.arabicDisplay, showEnglish ? narration.englishDisplay : AttributedString()]
        let visible = SearchMatch.visibleBlocks(blocks, preferred: locale.language.languageCode?.identifier == "ar" || !showEnglish ? 0 : 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(narration.chapter.bookTitle(locale: locale))
                .font(.caption).foregroundStyle(.secondary)
            if !narration.chapter.chapterTitle(locale: locale).isEmpty {
                Text(narration.chapter.chapterTitle(locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let number = narration.displayNumber {
                Text(number.formatted(.number.grouping(.never)))
                    .font(.headline)
            }
            if !narration.arabic.isEmpty, !searching || visible.contains(0) {
                SearchMatchText(narration.arabicDisplay)
                    .readingText(arabic: true, hadith: true)
                    .lineLimit(searching ? 2 : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if showEnglish, !narration.english.isEmpty, !searching || visible.contains(1) {
                SearchMatchText(narration.englishDisplay)
                    .readingText()
                    .lineLimit(searching ? 2 : 5)
                    .accessibilityIdentifier("hadith-preview-english-\(narration.id)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .readingColumn()
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
