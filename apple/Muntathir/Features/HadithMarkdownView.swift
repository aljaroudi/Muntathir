import SwiftUI

struct HadithMarkdownView: View {
    let text: AttributedString
    var arabic = false
    var adjustable = true
    var highlights: [ReadingHighlight] = []
    var block = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HadithText.paragraphs(text)) { paragraph in
                HStack(alignment: .top, spacing: 8) {
                    if let marker = paragraph.marker {
                        Text(marker).readingText(arabic: arabic, hadith: true, heading: paragraph.heading, adjustable: adjustable)
                    }
                    if paragraph.quoted {
                        Rectangle().fill(.secondary).frame(width: 3)
                    }
                    Group {
                        if highlights.isEmpty {
                            Text(paragraph.text)
                        } else {
                            ShareHighlightText(text: paragraph.text, highlights: highlights, block: block,
                                               sourceText: HighlightTextContent.canonical(text), offset: offset(for: paragraph))
                        }
                    }
                    .readingText(arabic: arabic, hadith: true, heading: paragraph.heading, adjustable: adjustable)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private func offset(for paragraph: HadithParagraph) -> Int {
        var offset = 0
        for item in HadithText.paragraphs(text) {
            offset += ((item.marker.map { $0 + " " } ?? "") + (item.quoted ? "│ " : "")).utf16.count
            if item.id == paragraph.id {
                return offset
            }
            offset += String(item.text.characters).utf16.count + 2
        }
        return offset
    }
}
