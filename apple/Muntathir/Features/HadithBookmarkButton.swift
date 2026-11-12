import SwiftUI

struct HadithBookmarkButton: View {
    let narration: Hadith
    @Binding var failed: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        BookmarkButton(source: narration.source?.key ?? "", isHadith: true,
                       excerpt: HighlightTextContent.canonical(narration.arabicDisplay),
                       reference: HadithShareContent(narration: narration, showEnglish: false, locale: locale).reference, failed: $failed)
    }
}
