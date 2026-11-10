import SwiftUI

struct QuranView: View {
    @State private var reader = QuranReader()
    @State private var query = Self.initialQuery

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
        QuranSearchContent(query: $query, reader: reader)
            .navigationTitle("The Holy Quran")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Surah, 2:255, or Quran text")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    QuranTranslationPicker()
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
    var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ayah.id).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Verse \(ayah.id)"))
                ReadingTimeHint(words: ReadingTime.words(arabic: ayah.text))
                Spacer()
                VerseActions(ayah: ayah, translation: translation)
            }
            if preview {
                AyahText(ayah: ayah).lineLimit(3)
            } else {
                HighlightText(text: ayah.text, source: ayah.id, block: "arabic", arabic: true)
                    .accessibilityIdentifier("quran-arabic-\(ayah.id)")
            }
            if let translation, let text = ayah.translations[translation.id] {
                Group {
                    if preview {
                        Text(text).readingText().lineLimit(3)
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
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
    }
}
