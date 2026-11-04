import SwiftUI

struct HadithPreviewRow: View {
    let narration: Hadith
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(narration.chapter.bookTitle(locale: locale))
                .font(.caption).foregroundStyle(.secondary)
            if !narration.chapter.chapterTitle(locale: locale).isEmpty {
                Text(narration.chapter.chapterTitle(locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(narration.number.formatted(.number.grouping(.never)))
                .font(.headline)
            if !narration.arabic.isEmpty {
                Text(narration.arabicDisplay)
                    .readingText(arabic: true, hadith: true)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if showEnglish, !narration.english.isEmpty {
                Text(narration.englishDisplay)
                    .readingText()
                    .lineLimit(5)
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
