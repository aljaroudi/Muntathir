import SwiftUI

/// A read-only preview: loading it never touches the navigation session or highlights.
struct HadithPeekView: View {
    let id: Int
    let reader: HadithReader
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @State private var narration: Hadith?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let narration {
                    if let number = narration.displayNumber {
                        Text(number.formatted(.number.grouping(.never))).font(.headline)
                    }
                    if !narration.arabic.isEmpty {
                        HadithMarkdownView(text: narration.arabicDisplay, arabic: true)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    if showEnglish, !narration.english.isEmpty {
                        HadithMarkdownView(text: narration.englishDisplay)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                } else if failed {
                    Text("Unable to load Hadith")
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .readingBackground()
        .frame(idealWidth: 360, idealHeight: 440)
        .accessibilityIdentifier("hadith-peek")
        .task(id: id) {
            do {
                let detail = try await reader.detail(id: id)
                try Task.checkCancellation()
                narration = detail.narration
            } catch is CancellationError {
            } catch {
                failed = true
            }
        }
    }
}
