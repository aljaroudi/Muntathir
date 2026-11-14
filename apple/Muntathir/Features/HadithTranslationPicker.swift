import SwiftUI

struct HadithTranslationPicker: View {
    @AppStorage("hadithEnglishEnabled.v2") private var showEnglish = SupplicationTranslation.prefersEnglish()
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Toggle(locale.localizedString(forLanguageCode: "en") ?? "English", isOn: $showEnglish)
                .accessibilityIdentifier("hadith-translation-english")
        } label: {
            Label("Translations", systemImage: "character.bubble")
        }
        .accessibilityIdentifier("hadith-translation-picker")
        .appTip(.translations)
        .onChange(of: showEnglish) { AppTip.complete(.translations) }
        .accessibilityValue(showEnglish ? (locale.localizedString(forLanguageCode: "en") ?? "English") : String(localized: "None"))
    }
}
