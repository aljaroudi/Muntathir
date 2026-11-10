import SwiftUI

struct VerseActionHost<Content: View>: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var contextMenu = true
    @ViewBuilder var content: () -> Content
    @Environment(\.locale) private var locale
    @State private var sharedImage: SharedAyah?
    @State private var copied = false
    @State private var editing: ReadingHighlight?
    @Environment(\.quranUserStore) private var store
    @State private var shareFailed = false

    var body: some View {
        Group {
            if contextMenu {
                content().contextMenu { actions }
            } else {
                Menu { actions } label: { content() }
            }
        }
        .sheet(item: $sharedImage) { AyahShareSheet(image: $0.image) }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: store?.highlights.contains { $0.id == value.id } == true)
        }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to create image", isPresented: $shareFailed) { Button("OK", role: .cancel) {} }
    }

    @ViewBuilder private var actions: some View {
        let canShare = AyahImageRenderer.canShare(ayah, locale: locale, translation: translation)
        Button("Copy text", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = VerseShareContent(ayah: ayah, translation: translation, locale: locale).text
            if !contextMenu {
                copied = true
            }
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
    }
}
