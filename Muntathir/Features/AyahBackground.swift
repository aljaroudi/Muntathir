import SwiftUI

struct AyahBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.07, green: 0.18, blue: 0.16), Color(red: 0.12, green: 0.15, blue: 0.17)]
                : [Color(red: 0.89, green: 0.95, blue: 0.90), Color(red: 0.98, green: 0.96, blue: 0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkle")
                .font(.system(size: 110, weight: .ultraLight))
                .foregroundStyle(Color.accentColor.opacity(0.06))
                .offset(x: 28, y: -36)
        }
        .accessibilityHidden(true)
    }
}

