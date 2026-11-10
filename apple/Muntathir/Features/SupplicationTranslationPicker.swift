import SwiftUI

struct SupplicationTranslationPicker: View {
    let languages: [String]
    @AppStorage("supplicationTranslation") private var selection = "auto"
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker("Translation", selection: $selection) {
                Text("Auto").tag("auto")
                Text("None").tag("none")
                ForEach(languages, id: \.self) { language in
                    Text(locale.localizedString(forLanguageCode: language) ?? language).tag(language)
                }
            }
        } label: {
            Label("Translation", systemImage: "character.bubble")
        }
        .accessibilityIdentifier("supplication-translation-picker")
    }
}
