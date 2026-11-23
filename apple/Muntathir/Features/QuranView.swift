import SwiftUI

struct QuranView: View {
    private let reader = QuranReader.shared
    @State private var query = Self.initialQuery
    @State private var submittedQuery = Self.initialQuery

    private static var initialQuery: String {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"), arguments.contains("--marketing-capture"),
               arguments.contains("--screenshot-verse")
            {
                return "94:6"
            }
        #endif
        return ""
    }

    var body: some View {
        AdaptiveSplit(restorationKey: "quran", defaultSelection: .quran(.surah(1))) { selection in
            list(selection: selection)
        }
    }

    private func list(selection: Binding<FigureRoute?>) -> some View {
        QuranSearchContent(submittedQuery: submittedQuery, reader: reader, selection: selection)
            .readingBackground()
            .navigationTitle("Holy Quran")
            .searchable(text: $query, placement: .alwaysVisible, prompt: "Surah, 2:255, or Quran text")
            .searchHistory($query, area: .quran)
            .submitsSearch($query, submitted: $submittedQuery)
            .intentSearch(.quran) { query = $0; submittedQuery = $0 }
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Menu {
                        QuranTranslationPicker()
                    } label: {
                        Label("Reading options", systemImage: "textformat")
                    }.accessibilityIdentifier("quran-reading-options")
                        .appTip(.translations)
                }
            }
    }
}

/// What the Quran list opens: pushed in a stack, or beside the list in a split view.
enum QuranSelection: Hashable, Codable, Sendable {
    case saved
    case surah(Int)
    case verse(surah: Int, verse: Int, query: String)
}

/// The reader for a Quran list selection.
struct QuranSelectionDetail: View {
    let selection: QuranSelection
    private let reader = QuranReader.shared
    private let surahs = QuranSurah.bundled

    var body: some View {
        switch selection {
        case .saved:
            QuranSavedVersesView(reader: reader, surahs: surahs)
        case let .surah(id):
            if let surah = surahs.first(where: { $0.id == id }) {
                QuranReadingView(surah: surah, reader: reader)
                    .onscreenEntity(SurahEntity.self, id: id)
            }
        case let .verse(id, verse, query):
            if let surah = surahs.first(where: { $0.id == id }) {
                QuranReadingView(surah: surah, initialVerse: verse, reader: reader, searchQuery: query)
                    .onscreenEntity(SurahEntity.self, id: id)
            }
        }
    }
}

struct QuranTranslationPicker: View {
    @Environment(\.locale) private var locale
    @State private var store = QuranTranslationStore.shared

    var body: some View {
        Menu {
            Button {
                store.select("auto")
                if !store.activeID.isEmpty, !store.isInstalled(store.activeID) {
                    store.downloadRequest = QuranTranslation.catalog.first { $0.id == store.activeID }
                }
            } label: {
                Label("Auto", systemImage: store.selection == "auto" ? "checkmark" : "globe")
            }
            Button { store.select("") } label: {
                Label("None", systemImage: store.selection.isEmpty ? "checkmark" : "minus")
            }
            .accessibilityIdentifier("quran-translation-none")
            ForEach(QuranTranslation.catalog) { translation in
                Button {
                    store.select(translation.id)
                    if !store.isInstalled(translation.id) {
                        store.downloadRequest = translation
                    }
                } label: {
                    Label(locale.localizedString(forIdentifier: translation.language) ?? translation.language,
                          systemImage: symbol(for: translation.id))
                }.accessibilityIdentifier("quran-translation-option-\(translation.id)")
            }
        } label: {
            Label("Translation", systemImage: "character.bubble")
        }
        .accessibilityIdentifier("quran-translation-picker")
        .onChange(of: store.selection) { AppTip.complete(.translations) }
        .accessibilityValue(QuranTranslation.catalog.first { $0.id == store.activeID }?.translator ?? String(localized: "None"))
    }

    private func symbol(for id: String) -> String {
        if !store.isInstalled(id) {
            return "arrow.down.circle"
        }
        if store.selection == id {
            return "checkmark"
        }
        return "character.bubble"
    }
}

struct QuranVerseRow: View {
    let ayah: Ayah
    let translation: QuranTranslation?
    var searchQuery = ""
    var preview = false
    var showsActions = true
    /// Search previews prepared by the reader; rows without one highlight while rendering.
    var highlight: QuranSearchHighlight?
    @Environment(\.locale) private var locale

    var body: some View {
        let arabic = highlight?.arabic ?? SearchMatch.text(ayah.text, query: searchQuery)
        let translated = highlight?.translation ?? SearchMatch.text(translation.flatMap { ayah.translations[$0.id] } ?? "", query: searchQuery)
        let visible = SearchMatch.visibleBlocks([arabic, translated], preferred: locale.language.languageCode?.identifier == "ar" ? 0 : 1)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(QuranReference.display(ayah.id, locale: locale)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Verse \(QuranReference.display(ayah.id, locale: locale))"))
                Spacer()
                if showsActions {
                    VerseActions(ayah: ayah, translation: translation)
                } else {
                    Color.clear.frame(width: 44, height: 28).accessibilityHidden(true)
                }
            }
            if preview {
                if visible.contains(0) {
                    SearchMatchText(highlight == nil ? SearchMatch.preview(arabic, compact: true) : arabic)
                        .readingText(arabic: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineLimit(2)
                }
            } else {
                HighlightText(text: ayah.text, source: ayah.id, block: "arabic", arabic: true)
                    .accessibilityIdentifier("quran-arabic-\(ayah.id)")
            }
            if let translation, let text = ayah.translations[translation.id], !preview || visible.contains(1) {
                Group {
                    if preview {
                        SearchMatchText(highlight == nil ? SearchMatch.preview(translated, compact: true) : translated).readingText().lineLimit(2)
                    } else {
                        HighlightText(text: text, source: ayah.id, block: translation.id)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, Locale(identifier: translation.language).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                .accessibilityIdentifier("quran-translation-\(ayah.id)")
            }
        }
        .readingColumn()
        .padding(.vertical, 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityElement(children: .contain)
    }
}
