import SwiftUI

/// Picks the trusted (bundled) translation shown alongside hadith or supplications.
struct TranslationPicker: View {
    /// Supplication translation languages, or nil for hadith, which offer their bundled English.
    var supplicationLanguages: [String]?
    @AppStorage("supplicationTranslation.v2") private var supplicationSelection = "auto"
    @AppStorage("hadithEnglishEnabled.v2") private var showEnglish = SupplicationTranslation.prefersEnglish()
    @Environment(\.locale) private var locale

    private var english: String {
        locale.localizedString(forLanguageCode: "en") ?? "English"
    }

    var body: some View {
        Menu {
            if let languages = supplicationLanguages {
                Picker("Translation", selection: $supplicationSelection) {
                    Text("Auto").tag("auto")
                    Text("None").tag("none")
                    ForEach(languages, id: \.self) { language in
                        Text(locale.localizedString(forLanguageCode: language) ?? language).tag(language)
                    }
                }
            } else {
                Toggle(english, isOn: $showEnglish)
                    .accessibilityIdentifier("hadith-translation-english")
            }
        } label: {
            Label("Translation", systemImage: "character.bubble")
        }
        .accessibilityIdentifier(supplicationLanguages == nil ? "hadith-translation-picker" : "supplication-translation-picker")
        .accessibilityValue(accessibilityValue)
        .appTip(.translations)
        .onChange(of: supplicationSelection) { AppTip.complete(.translations) }
        .onChange(of: showEnglish) { AppTip.complete(.translations) }
    }

    private var accessibilityValue: String {
        if supplicationLanguages != nil {
            switch supplicationSelection {
            case "auto": return String(localized: "Auto")
            case "none": return String(localized: "None")
            default: return locale.localizedString(forLanguageCode: supplicationSelection) ?? supplicationSelection
            }
        }
        return showEnglish ? english : String(localized: "None")
    }
}
