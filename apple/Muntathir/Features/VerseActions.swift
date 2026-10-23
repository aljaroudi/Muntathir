import SwiftUI

struct VerseShareContent {
    let ayah: Ayah
    let translation: QuranTranslation?
    let reference: String
    private static let surahs = (try? QuranSurah.load()) ?? []

    init(ayah: Ayah, translation: QuranTranslation?, locale: Locale) {
        self.ayah = ayah
        self.translation = translation
        let name = Self.surahs.first { $0.id == ayah.surah }?.title(locale: locale)
        reference = [name, ayah.id].compactMap(\.self).joined(separator: " · ")
    }

    var translatedText: String? {
        translation.flatMap { ayah.translations[$0.id] }
    }

    var text: String {
        [ayah.text, translatedText, translatedText == nil ? nil : translation?.translator, reference]
            .compactMap(\.self).joined(separator: "\n\n")
    }
}

struct VerseActions: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var identifier: String?
    @Environment(\.locale) private var locale
    @Environment(\.quranUserStore) private var store
    @State private var sharedImage: SharedAyah?
    @State private var editingNote = false
    @State private var copied = false
    @State private var saveFailed = false
    @State private var shareFailed = false

    private var state: QuranVerseState {
        store?.state(for: ayah.id) ?? QuranVerseState(id: ayah.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            if state.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Favorite")
                    .accessibilityIdentifier("verse-favorite-\(ayah.id)")
            }
            if !state.note.isEmpty {
                Image(systemName: "note.text").foregroundStyle(.secondary)
                    .accessibilityLabel("Has note")
                    .accessibilityIdentifier("verse-has-note-\(ayah.id)")
            }
            Menu {
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
                Divider()
                Button {
                    do {
                        guard let store else { throw QuranUserStoreError.unavailable }
                        try store.setFavorite(!state.isFavorite, for: ayah.id)
                    } catch { saveFailed = true }
                } label: {
                    if state.isFavorite {
                        Label("Remove favorite", systemImage: "star.slash")
                    } else {
                        Label("Favorite", systemImage: "star")
                    }
                }
                Button {
                    editingNote = true
                } label: {
                    if state.note.isEmpty {
                        Label("Add note", systemImage: "square.and.pencil")
                    } else {
                        Label("Edit note", systemImage: "square.and.pencil")
                    }
                }
            } label: {
                Label("Verse actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier(identifier ?? "verse-actions-\(ayah.id)")
            .accessibilityLabel(Text("Actions for verse \(ayah.id)"))
        }
        .sheet(item: $sharedImage) { AyahShareSheet(image: $0.image) }
        .sheet(isPresented: $editingNote) {
            VerseNoteEditor(verseID: ayah.id, initialNote: state.note)
        }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your change was not saved. Please try again.") }
        .alert("Unable to create image", isPresented: $shareFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try sharing the verse again.") }
    }
}
