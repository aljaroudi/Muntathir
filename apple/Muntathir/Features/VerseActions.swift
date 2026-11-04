import SwiftUI

struct VerseShareContent {
    let ayah: Ayah
    let translation: QuranTranslation?
    let reference: String
    let imageReference: String
    private static let arabicDigits = Array("٠١٢٣٤٥٦٧٨٩")
    private static let surahs = (try? QuranSurah.load()) ?? []

    init(ayah: Ayah, translation: QuranTranslation?, locale: Locale) {
        self.ayah = ayah
        self.translation = translation
        let name = Self.surahs.first { $0.id == ayah.surah }?.title(locale: locale)
        reference = [name, ayah.id].compactMap(\.self).joined(separator: " · ")
        if locale.language.languageCode?.identifier == "ar", let name {
            // Image references use Arabic-Indic digits regardless of the device's numbering preference.
            let number = String(ayah.number).compactMap(\.wholeNumberValue).map { String(Self.arabicDigits[$0]) }.joined()
            imageReference = name + " " + number
        } else {
            imageReference = ayah.id
        }
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
    let ayah: Ayah
    let translation: QuranTranslation?
    var identifier: String?
    @Environment(\.locale) private var locale
    @State private var sharedImage: SharedAyah?
    @State private var copied = false
    @State private var editing: ReadingHighlight?
    @Environment(\.quranUserStore) private var store
    @State private var shareFailed = false

    var body: some View {
        Menu {
            let canShare = AyahImageRenderer.canShare(ayah, locale: locale, translation: translation)
            Button("Copy text", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = VerseShareContent(ayah: ayah, translation: translation, locale: locale).text
                copied = true
            }
            Button("Share as image", systemImage: "square.and.arrow.up") {
                if let image = AyahImageRenderer.image(for: ayah, locale: locale, translation: translation) {
                    sharedImage = SharedAyah(image: image)
                } else {
                    shareFailed = true
                }
            }
            .disabled(!canShare)
            Divider()
            HighlightActions(source: ayah.id, isHadith: false, excerpt: ayah.text, reference: ayah.id, editing: $editing)
        } label: {
            Label("Verse actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier(identifier ?? "verse-actions-\(ayah.id)")
        .accessibilityLabel(Text("Actions for verse \(ayah.id)"))
        .sheet(item: $sharedImage) { AyahShareSheet(image: $0.image) }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: store?.highlights.contains { $0.id == value.id } == true)
        }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to create image", isPresented: $shareFailed) { Button("OK", role: .cancel) {} }
    }
}

struct HadithShareContent {
    let narration: Hadith
    let showEnglish: Bool
    let locale: Locale

    var reference: String {
        narration.chapter.title(locale: locale) + " · " + String(narration.number)
    }

    var text: String {
        ([narration.arabic] + (showEnglish ? [narration.englishNarrator, narration.english] : []) + [reference])
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var body: String {
        ([narration.arabic] + (showEnglish ? [narration.englishNarrator, narration.english] : []))
            .filter { !$0.isEmpty }.map { String(HadithText.markdown($0).characters) }.joined(separator: "\n\n")
    }
}

@MainActor enum HadithImageRenderer {
    static func canShare(_ content: HadithShareContent) -> Bool {
        ShareImageRenderer.canShare(HadithShareArtwork(content: content), locale: content.locale)
    }

    static func image(for content: HadithShareContent) -> UIImage? {
        ShareImageRenderer.image(HadithShareArtwork(content: content), locale: content.locale)
    }
}

struct HadithShareArtwork: View {
    let content: HadithShareContent

    var body: some View {
        ShareArtwork(reference: content.reference) {
            if !content.narration.arabic.isEmpty {
                HadithMarkdownView(text: HadithText.markdown(content.narration.arabic), arabic: true, adjustable: false)
                    .padding()
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if content.showEnglish {
                if !content.narration.englishNarrator.isEmpty {
                    HadithMarkdownView(text: HadithText.markdown(content.narration.englishNarrator), adjustable: false)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if !content.narration.english.isEmpty {
                    HadithMarkdownView(text: HadithText.markdown(content.narration.english), adjustable: false)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}

struct HadithActions: View {
    @Binding var textSizePresented: Bool
    let narration: Hadith
    @Environment(\.locale) private var locale
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @State private var shared: SharedAyah?
    @State private var shareFailed = false
    @State private var copied = false
    @State private var editing: ReadingHighlight?
    @Environment(\.quranUserStore) private var store

    private var content: HadithShareContent {
        .init(narration: narration, showEnglish: showEnglish, locale: locale)
    }

    var body: some View {
        Menu {
            let canShare = HadithImageRenderer.canShare(content)
            Button("Copy text", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = content.text
                copied = true
            }
            Button("Share as image", systemImage: "square.and.arrow.up") {
                if let image = HadithImageRenderer.image(for: content) {
                    shared = SharedAyah(image: image)
                } else {
                    shareFailed = true
                }
            }
            .disabled(!canShare)
            Divider()
            HadithTranslationPicker()
            ReadingSizeMenu(isPresented: $textSizePresented)
            HighlightActions(source: narration.source?.key ?? "", isHadith: true, excerpt: content.body, reference: content.reference, editing: $editing)
        } label: {
            Label("Hadith actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("hadith-actions")
        .sheet(item: $shared) { AyahShareSheet(image: $0.image) }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: store?.highlights.contains { $0.id == value.id } == true)
        }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to create image", isPresented: $shareFailed) { Button("OK", role: .cancel) {} }
    }
}
