import SwiftUI

struct HadithHighlightButton: View {
    let narration: Hadith
    @Environment(\.locale) private var locale
    @State private var editing = false

    var body: some View {
        Button("Highlight", systemImage: "highlighter") { editing = true }
            .disabled(narration.source == nil)
            .accessibilityIdentifier("hadith-highlight")
            .sheet(isPresented: $editing) {
                HighlightEditor(highlight: ReadingHighlight(source: narration.source?.key ?? "", isHadith: true,
                                                            excerpt: HighlightTextContent.canonical(narration.arabicDisplay),
                                                            reference: HadithShareContent(narration: narration, showEnglish: false, locale: locale).reference))
            }
    }
}
