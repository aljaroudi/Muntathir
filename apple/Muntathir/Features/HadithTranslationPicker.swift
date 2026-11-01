import SwiftUI

struct HadithTranslationPicker: View {
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Toggle(locale.localizedString(forLanguageCode: "en") ?? "English", isOn: $showEnglish)
                .accessibilityIdentifier("hadith-translation-english")
        } label: {
            Label("Translations", systemImage: "character.bubble")
        }
        .accessibilityIdentifier("hadith-translation-picker")
        .accessibilityValue(showEnglish ? (locale.localizedString(forLanguageCode: "en") ?? "English") : String(localized: "None"))
    }
}
