import SwiftUI

enum ReadingBackground: String, CaseIterable {
    case system, warmPaper, softGray

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .warmPaper: "Warm Paper"
        case .softGray: "Soft Gray"
        }
    }

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .system: Color(uiColor: .systemBackground)
        case .warmPaper:
            scheme == .dark ? Color(red: 0.13, green: 0.115, blue: 0.09)
                : Color(red: 0.98, green: 0.95, blue: 0.88)
        case .softGray:
            scheme == .dark ? Color(white: 0.12) : Color(white: 0.93)
        }
    }
}

struct ReadingBackgroundPicker: View {
    @AppStorage("readingBackground") private var background: ReadingBackground = .warmPaper

    var body: some View {
        Picker("Background", selection: $background) {
            ForEach(ReadingBackground.allCases, id: \.self) { option in
                Text(option.title).tag(option)
                    .accessibilityIdentifier("reading-background-\(option.rawValue)")
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("reading-background")
    }
}

private struct ReadingBackgroundColor: View {
    @AppStorage("readingBackground") private var background: ReadingBackground = .warmPaper
    @Environment(\.colorScheme) private var scheme

    var body: some View { background.color(for: scheme) }
}

extension View {
    func readingBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(ReadingBackgroundColor().ignoresSafeArea())
    }

    func readingRowBackground() -> some View {
        listRowBackground(ReadingBackgroundColor())
    }
}
