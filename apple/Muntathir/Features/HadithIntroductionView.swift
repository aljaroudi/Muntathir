import SwiftUI

struct HadithIntroductionRow: View {
    let introduction: HadithIntroduction
    let reader: HadithReader
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationLink {
            HadithIntroductionView(introduction: introduction, reader: reader)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Introduction").font(.headline)
                if introduction.hasSpecificTitle {
                    Text(introduction.title).font(.subheadline)
                }
            }
        }
        .accessibilityIdentifier("hadith-introduction-\(introduction.id)")
    }
}

struct HadithIntroductionView: View {
    let introduction: HadithIntroduction
    let reader: HadithReader
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @Environment(\.locale) private var locale
    @State private var textSizePresented = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var arabic = AttributedString()
    @State private var english = AttributedString()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    ProgressView()
                } else if failed {
                    HadithLoadError { retry += 1 }
                }
                if introduction.hasSpecificTitle {
                    Text(introduction.title).font(.subheadline)
                }
                if !arabic.characters.isEmpty {
                    HadithMarkdownView(text: arabic, arabic: true)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if showEnglish || arabic.characters.isEmpty, !english.characters.isEmpty {
                    HadithMarkdownView(text: english)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .readingColumn()
            .padding()
        }
        .readingBackground()
        .navigationTitle("Introduction")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("hadith-introduction-reader")
        .toolbar {
            Menu {
                HadithTranslationPicker()
                ReadingSizeMenu(isPresented: $textSizePresented)
            } label: {
                Label("Reading options", systemImage: "textformat")
            }
            .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
        }
        .task(id: retry) {
            loading = true
            failed = false
            do {
                let content = try await reader.introduction(id: introduction.id)
                try Task.checkCancellation()
                arabic = HadithText.markdown(content.arabic)
                english = HadithText.markdown(content.english)
                loading = false
            } catch is CancellationError {
            } catch {
                failed = true
                loading = false
            }
        }
    }
}
