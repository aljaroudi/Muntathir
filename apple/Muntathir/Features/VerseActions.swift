import SwiftUI

struct VerseShareContent {
    let ayah: Ayah
    let translation: QuranTranslation?
    let reference: String
    var imageReference: String {
        reference
    }

    init(ayah: Ayah, translation: QuranTranslation?, locale: Locale) {
        self.ayah = ayah
        self.translation = translation
        reference = QuranReference.display(ayah.id, locale: locale)
    }

    var translatedText: String? {
        translation.flatMap { ayah.translations[$0.id] }
    }

    var text: String {
        [ayah.text, translatedText, reference]
            .compactMap(\.self).joined(separator: "\n\n")
    }
}

struct VerseActions: View {
    @Environment(\.locale) private var locale
    let ayah: Ayah
    let translation: QuranTranslation?
    var identifier: String?
    var body: some View {
        VerseActionHost(ayah: ayah, translation: translation, contextMenu: false) {
            Label("Verse actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier(identifier ?? "verse-actions-\(ayah.id)")
        .accessibilityLabel(Text("Actions for verse \(QuranReference.display(ayah.id, locale: locale))"))
    }
}

struct HadithShareContent {
    let narration: Hadith
    let showEnglish: Bool
    let locale: Locale

    var reference: String {
        if narration.isSupplication {
            return narration.chapter.title(locale: locale)
        }
        return narration.chapter.bookTitle(locale: locale) + (narration.displayNumber.map { " • " + String($0) } ?? "")
    }

    private var translatedTexts: [String] {
        if narration.isSupplication {
            return narration.translation.map { [$0.text] } ?? []
        }
        return showEnglish ? [narration.englishNarrator, narration.english] : []
    }

    var text: String {
        ([narration.arabic] + translatedTexts + [reference])
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var body: String {
        ([narration.arabic] + translatedTexts)
            .filter { !$0.isEmpty }.map { String(HadithText.markdown($0).characters) }.joined(separator: "\n\n")
    }
}

@MainActor enum HadithImageRenderer {
    static func canShare(_ content: HadithShareContent, highlights: [ReadingHighlight] = []) -> Bool {
        ShareImageRenderer.canShare(HadithShareArtwork(content: content, highlights: highlights), locale: content.locale)
    }

    static func image(for content: HadithShareContent, highlights: [ReadingHighlight] = []) -> UIImage? {
        ShareImageRenderer.image(HadithShareArtwork(content: content, highlights: highlights), locale: content.locale)
    }
}

struct HadithShareArtwork: View {
    let content: HadithShareContent
    var highlights: [ReadingHighlight] = []

    var body: some View {
        ShareArtwork(reference: content.reference) {
            if !content.narration.arabic.isEmpty {
                HadithMarkdownView(text: HadithText.markdown(content.narration.arabic), arabic: true, adjustable: false, highlights: highlights, block: "arabic")
                    .padding()
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if let translation = content.narration.translation {
                HadithMarkdownView(text: HadithText.markdown(translation.text), adjustable: false, highlights: highlights, block: translation.block)
                    .environment(\.layoutDirection, translation.isRightToLeft ? .rightToLeft : .leftToRight)
            }
            if !content.narration.isSupplication, content.showEnglish {
                if !content.narration.englishNarrator.isEmpty {
                    HadithMarkdownView(text: HadithText.markdown(content.narration.englishNarrator), adjustable: false, highlights: highlights, block: "englishNarrator")
                        .environment(\.layoutDirection, .leftToRight)
                }
                if !content.narration.english.isEmpty {
                    HadithMarkdownView(text: HadithText.markdown(content.narration.english), adjustable: false, highlights: highlights, block: "english")
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}

struct HadithActions: View {
    @Binding var textSizePresented: Bool
    let narration: Hadith
    var translationLanguages: [String] = []
    @Environment(\.locale) private var locale
    @Environment(\.quranUserStore) private var store
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    private struct ShareItem: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    @State private var shared: ShareItem?
    @State private var copied = false
    @State private var bookmarkFailed = false

    private var content: HadithShareContent {
        .init(narration: narration, showEnglish: showEnglish, locale: locale)
    }

    private var highlights: [ReadingHighlight] {
        guard let source = narration.source?.key else { return [] }
        return store?.highlights(for: source, isHadith: true) ?? []
    }

    var body: some View {
        Menu {
            let canShare = HadithImageRenderer.canShare(content, highlights: highlights)
            Button("Copy text", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = content.text
                copied = true
            }
            let shareTitle: LocalizedStringKey = canShare ? "Share as image" : "Share"
            Button(shareTitle, systemImage: "square.and.arrow.up") {
                if canShare, let image = HadithImageRenderer.image(for: content, highlights: highlights) {
                    shared = ShareItem(items: [image])
                } else {
                    shared = ShareItem(items: [content.text])
                }
            }
            Divider()
            if narration.isSupplication {
                SupplicationTranslationPicker(languages: translationLanguages)
            } else {
                HadithTranslationPicker()
            }
            ReadingSizeMenu(isPresented: $textSizePresented)
            BookmarkButton(source: narration.source?.key ?? "", isHadith: true, excerpt: content.body, reference: content.reference, failed: $bookmarkFailed)
        } label: {
            Label(LocalizedStringKey(narration.isSupplication ? "Supplication actions" : "Hadith actions"), systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("hadith-actions")
        .sheet(item: $shared) { AyahShareSheet(items: $0.items) }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to save bookmark", isPresented: $bookmarkFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try again.") }
    }
}
