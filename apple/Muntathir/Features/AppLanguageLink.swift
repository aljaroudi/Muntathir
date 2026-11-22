import SwiftUI

struct AppLanguageLink: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("App language", systemImage: "globe") {
            openURL(Self.settingsURL)
        }
        .accessibilityIdentifier("app-language-settings")
    }

    private static var settingsURL: URL {
        #if os(macOS)
            // Per-app languages live in System Settings › General › Language & Region.
            URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        #else
            URL(string: UIApplication.openSettingsURLString)!
        #endif
    }
}
