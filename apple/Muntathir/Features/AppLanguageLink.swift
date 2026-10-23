import SwiftUI
import UIKit

struct AppLanguageLink: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("App language", systemImage: "globe") {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        .accessibilityIdentifier("app-language-settings")
    }
}
