import SwiftUI

struct HadithIntroductionRow: View {
    let introduction: HadithIntroduction
    let reader: HadithReader

    var body: some View {
        NavigationLink {
            HadithIntroductionView(introduction: introduction, reader: reader)
        } label: {
            Text("Introduction").font(.headline)
        }
        .accessibilityIdentifier("hadith-introduction-\(introduction.id)")
    }
}

struct HadithIntroductionView: View {
    let introduction: HadithIntroduction
    let reader: HadithReader
    var highlight: ReadingHighlight?
    @AppStorage("hadithEnglishEnabled.v2") private var showEnglish = SupplicationTranslation.prefersEnglish()
    @State private var textSizePresented = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.locale) private var locale
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var arabic: HighlightBlock?
    @State private var english: HighlightBlock?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if loading {
                        ProgressView()
                    } else if failed {
                        HadithLoadError { retry += 1 }
                    }
                    if let arabic, !arabic.text.isEmpty {
                        segments(arabic, arabic: true)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    if let english, !english.text.isEmpty,
                       showEnglish || arabic?.text.isEmpty != false || highlight?.block == english.id
                    {
                        segments(english)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .readingColumn()
                .padding()
            }
            .task(id: retry) {
                loading = true
                failed = false
                do {
                    let content = try await reader.introduction(id: introduction.id)
                    let blocks = await Self.blocks(content)
                    try Task.checkCancellation()
                    (arabic, english) = blocks
                    loading = false
                    // Lazy segments only exist once scrolled to; bring the saved highlight's segment on screen first.
                    if let block = [blocks.0, blocks.1].first(where: { $0.id == highlight?.block }),
                       let segment = block.segment(for: highlight)
                    {
                        await Task.yield()
                        proxy.scrollTo("\(block.id):\(segment.id)", anchor: .top)
                    }
                } catch is CancellationError {
                } catch {
                    failed = true
                    loading = false
                }
            }
        }
        .environment(\.focusedHighlight, highlight)
        .readingBackground()
        .navigationTitle("Introduction")
        .inlineNavigationTitle()
        .accessibilityIdentifier("hadith-introduction-reader")
        .toolbar {
            Menu {
                TranslationPicker()
                ReadingSizeMenu(isPresented: $textSizePresented)
                ArabicDiacriticsToggle()
            } label: {
                Label("Reading options", systemImage: "textformat")
            }
            .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
        }
    }

    /// Parsing and splitting book-length introductions is too slow for the main actor.
    @concurrent private nonisolated static func blocks(_ content: HadithIntroduction) async -> (HighlightBlock, HighlightBlock) {
        (HighlightBlock(id: "arabic", markdown: HadithText.markdown(content.arabic)),
         HighlightBlock(id: "english", markdown: HadithText.markdown(content.english)))
    }

    private func segments(_ block: HighlightBlock, arabic: Bool = false) -> some View {
        ForEach(block.segments) { segment in
            HighlightText(text: segment.text, source: introduction.highlightSource, block: block.id,
                          isHadith: true, reference: introduction.bookTitle(locale: locale) + " · " + String(localized: "Introduction"),
                          arabic: arabic, markdown: segment.markdown, blockText: block.text, offset: segment.offset)
                .id("\(block.id):\(segment.id)")
        }
    }
}
