import SwiftUI

struct HadithMarkdownView: View {
    let text: AttributedString
    var arabic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HadithText.paragraphs(text)) { paragraph in
                HStack(alignment: .top, spacing: 8) {
                    if let marker = paragraph.marker {
                        Text(marker).readingText(arabic: arabic, heading: paragraph.heading)
                    }
                    if paragraph.quoted {
                        Rectangle().fill(.secondary).frame(width: 3)
                    }
                    Text(paragraph.text)
                        .readingText(arabic: arabic, heading: paragraph.heading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
