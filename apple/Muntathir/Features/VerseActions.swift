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
        [ayah.text, translatedText, reference]
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
                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Bookmark")
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
                        Label("Remove bookmark", systemImage: "bookmark.slash")
                    } else {
                        Label("Bookmark", systemImage: "bookmark")
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
    /// TextKit determines page breaks using the same fonts and width used to draw each page.
    static func pages(_ text: NSAttributedString) -> [NSAttributedString] {
        guard text.length > 0 else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var result: [NSAttributedString] = []
        var consumed = 0
        while consumed < text.length {
            let container = NSTextContainer(size: CGSize(width: 460, height: 1080))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let glyphs = layout.glyphRange(for: container)
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard range.length > 0 else { return [] }
            result.append(text.attributedSubstring(from: range))
            consumed = NSMaxRange(range)
        }
        return result
    }

    static func files(for content: HadithShareContent) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hadith-share-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        do {
            try render(content) { image in
                guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                let url = directory.appending(path: "Hadith-\(files.count + 1).png")
                try data.write(to: url, options: .atomic)
                files.append(url)
            }
            return files
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func render(_ content: HadithShareContent, receive: (UIImage) throws -> Void) throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        paragraph.baseWritingDirection = .natural
        let text = NSAttributedString(string: content.body, attributes: [
            .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ])
        let pages = pages(text)
        guard !pages.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let footerAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.darkGray]
        let referenceSize = (content.reference + "\nMuntathir · 999/999" as NSString).boundingRect(
            with: CGSize(width: 460, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: footerAttributes, context: nil
        )
        let footerHeight = max(100, ceil(referenceSize.height))
        let height = 1200 + footerHeight
        let background = ImageRenderer(content: AyahBackground().frame(width: 540, height: height).environment(\.colorScheme, .light))
        background.scale = 2
        guard let backdrop = background.uiImage else { throw CocoaError(.fileWriteUnknown) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        // Keep only one decoded page in memory, even for very long narrations.
        for (index, page) in pages.enumerated() {
            try autoreleasepool {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 540, height: height), format: format).image { _ in
                    backdrop.draw(in: CGRect(x: 0, y: 0, width: 540, height: height))
                    (String(localized: "Hadith") as NSString).draw(in: CGRect(x: 40, y: 30, width: 460, height: 40),
                                                                   withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: UIColor.darkGray])
                    page.draw(with: CGRect(x: 40, y: 85, width: 460, height: 1080), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    let footer = content.reference + "\nMuntathir" + (pages.count > 1 ? " · \(index + 1)/\(pages.count)" : "")
                    (footer as NSString).draw(with: CGRect(x: 40, y: 1185, width: 460, height: footerHeight),
                                              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: footerAttributes, context: nil)
                }
                try receive(image)
            }
        }
    }
}

private struct SharedHadith: Identifiable {
    let id = UUID()
    let files: [URL]
}

struct HadithActions: View {
    let narration: Hadith
    @Environment(\.quranUserStore) private var store
    @Environment(\.locale) private var locale
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @State private var editingNote = false
    @State private var shared: SharedHadith?
    @State private var shareDirectory: URL?
    @State private var shareFailed = false
    @State private var copied = false

    private var key: String {
        narration.source?.key ?? ""
    }

    private var state: QuranVerseState {
        store?.hadithState(for: key) ?? QuranVerseState(id: key)
    }

    private var content: HadithShareContent {
        .init(narration: narration, showEnglish: showEnglish, locale: locale)
    }

    var body: some View {
        Menu {
            Button("Copy text", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = content.text
                copied = true
            }
            Button("Share as image", systemImage: "square.and.arrow.up") {
                do {
                    let files = try HadithImageRenderer.files(for: content)
                    shareDirectory = files.first?.deletingLastPathComponent()
                    shared = SharedHadith(files: files)
                } catch { shareFailed = true }
            }
            Divider()
            HadithTranslationPicker()
            ReadingSizeMenu()
            Button { editingNote = true } label: {
                Label(state.note.isEmpty ? "Add note" : "Edit note", systemImage: "square.and.pencil")
            }.disabled(key.isEmpty)
        } label: {
            Label("Hadith actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("hadith-actions")
        .sheet(item: $shared, onDismiss: {
            if let shareDirectory {
                try? FileManager.default.removeItem(at: shareDirectory)
            }
            shareDirectory = nil
        }) { AyahShareSheet(files: $0.files) }
        .sheet(isPresented: $editingNote) {
            VerseNoteEditor(verseID: key, initialNote: state.note, isHadith: true, reference: content.reference)
        }
        .alert("Text copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        .alert("Unable to create image", isPresented: $shareFailed) { Button("OK", role: .cancel) {} }
    }
}
