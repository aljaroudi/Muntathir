import SwiftUI

@MainActor @Observable final class VerseActionState {
    var sharedImage: SharedAyah?
    var copied = false
    var editing: ReadingHighlight?
    var bookmarkFailed = false
    var shareFailed = false
}

struct VerseActionHost<Content: View>: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var contextMenu = true
    @ViewBuilder var content: () -> Content
    @State private var actions = VerseActionState()

    var body: some View {
        Group {
            if contextMenu {
                content().contextMenu { menu }
            } else {
                Menu { menu } label: { content() }
            }
        }
        .modifier(VerseActionPresentation(actions: actions))
    }

    private var menu: some View {
        VerseActionMenu(ayah: ayah, translation: translation, contextMenu: contextMenu, actions: actions)
    }
}

struct VerseActionPresentation: ViewModifier {
    @Bindable var actions: VerseActionState
    @Environment(\.quranUserStore) private var store

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.sharedImage) { AyahShareSheet(image: $0.image) }
            .sheet(item: $actions.editing) { value in
                HighlightEditor(highlight: value, existing: store?.highlights.contains { $0.id == value.id } == true)
            }
            .alert("Text copied", isPresented: $actions.copied) { Button("OK", role: .cancel) {} }
            .alert("Unable to save bookmark", isPresented: $actions.bookmarkFailed) { Button("OK", role: .cancel) {} }
            message: { Text("Please try again.") }
            .alert("Unable to create image", isPresented: $actions.shareFailed) { Button("OK", role: .cancel) {} }
    }
}

struct VerseActionMenu: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var contextMenu = true
    @Bindable var actions: VerseActionState
    @Environment(\.locale) private var locale

    var body: some View {
        Button("Copy text", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = VerseShareContent(ayah: ayah, translation: translation, locale: locale).text
            if !contextMenu {
                actions.copied = true
            }
        }
        Button("Share as image", systemImage: "square.and.arrow.up") {
            if let image = AyahImageRenderer.image(for: ayah, locale: locale, translation: translation) {
                actions.sharedImage = SharedAyah(image: image)
            } else {
                actions.shareFailed = true
            }
        }
        Divider()
        if contextMenu {
            HighlightActions(source: ayah.id, isHadith: false, excerpt: ayah.text, reference: ayah.id,
                             editing: $actions.editing, bookmarkFailed: $actions.bookmarkFailed)
        } else {
            BookmarkButton(source: ayah.id, isHadith: false, excerpt: ayah.text, reference: ayah.id, failed: $actions.bookmarkFailed)
        }
    }
}
