import SwiftUI

struct HadithDetailView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hadithAssets) private var assets
    @Environment(\.hadithSession) private var session
    @State private var textSizePresented = false
    @State private var bookmarkFailed = false
    @State private var scrollPosition = ScrollPosition()
    @State private var offset: Double = 0
    let initialID: Int
    let reader: HadithReader
    let query: String
    let orderedFallback: Bool
    var highlight: ReadingHighlight?
    var supplication = false

    private var isSupplication: Bool {
        detail?.narration.isSupplication ?? supplication
    }

    @AppStorage("supplicationTranslation") private var translation = "auto"
    @State private var translationLanguages: [String] = []
    @State private var translationChanged = false
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var currentID: Int?
    @State private var detail: HadithDetail?
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    ProgressView()
                } else if failed {
                    HadithLoadError(supplications: isSupplication) { Task { await assets?.refresh(); retry += 1 } }
                } else if let detail {
                    let narration = detail.narration
                    if isSupplication {
                        Text(narration.chapter.chapterTitle(locale: locale))
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("supplication-title")
                    } else {
                        Section {
                            if !detail.authorName(locale: locale).isEmpty {
                                metadata("Author", value: detail.authorName(locale: locale))
                                    .accessibilityIdentifier("hadith-detail-author")
                            }
                            metadata("Book", value: narration.chapter.bookTitle(locale: locale))
                                .accessibilityIdentifier("hadith-detail-book")
                            if !narration.chapter.chapterTitle(locale: locale).isEmpty {
                                metadata("Chapter", value: narration.chapter.chapterTitle(locale: locale))
                                    .accessibilityIdentifier("hadith-detail-chapter")
                            }
                        }
                        .readingRowBackground()
                    }
                    Section {
                        if !narration.arabic.isEmpty {
                            highlighted(narration.arabicDisplay, block: "arabic", narration: narration, arabic: true)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .accessibilityIdentifier("hadith-full-arabic")
                        }
                        if !isSupplication, showEnglish, !narration.englishNarrator.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Narrator").font(.subheadline).foregroundStyle(.secondary)
                                highlighted(narration.narratorDisplay, block: "englishNarrator", narration: narration)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .accessibilityIdentifier("hadith-detail-narrator")
                        }
                        if !isSupplication, showEnglish, !narration.english.isEmpty {
                            highlighted(narration.englishDisplay, block: "english", narration: narration)
                                .environment(\.layoutDirection, .leftToRight)
                                .accessibilityIdentifier("hadith-full-english")
                        }
                        if let translation = narration.translation {
                            highlighted(HadithText.highlighted(translation.text, terms: QuranSearchText.terms(query)), block: translation.block, narration: narration)
                                .environment(\.layoutDirection, translation.isRightToLeft ? .rightToLeft : .leftToRight)
                                .accessibilityIdentifier("supplication-full-translation")
                        }
                    }
                    .readingRowBackground()
                    let gradings = detail.gradings.filter {
                        $0.status == "judgment" && !$0.judgment(locale: locale).isEmpty
                    }
                    if !gradings.isEmpty {
                        Section("Grading") {
                            ForEach(gradings) { grading in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(grading.judgment(locale: locale))
                                        .font(.headline)
                                    if !grading.grader(locale: locale).isEmpty {
                                        Text(grading.grader(locale: locale))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !grading.reference(locale: locale).isEmpty {
                                        Text(grading.reference(locale: locale))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    if !isSupplication {
                        Section {
                            HStack {
                                Button("Previous") { session?.state.detailOffset = 0; currentID = detail.previousID }
                                    .disabled(detail.previousID == nil)
                                    .accessibilityIdentifier("hadith-previous")
                                Spacer()
                                Button("Next") { session?.state.detailOffset = 0; currentID = detail.nextID }
                                    .disabled(detail.nextID == nil)
                                    .accessibilityIdentifier("hadith-next")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .readingColumn()
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .readingBackground()
        .textSelection(.enabled)
        .environment(\.focusedHighlight, highlight)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, value in offset = value }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, !loading {
                session?.state.detailOffset = offset
            }
        }
        .onChange(of: loading) { _, loading in
            if !loading, highlight == nil {
                scrollPosition.scrollTo(y: session?.state.detailOffset ?? 0)
            }
        }
        .navigationTitle(detail?.narration.displayNumber.map { isSupplication ? String(localized: "Supplication \($0)") : String(localized: "Narration \($0)") }
            ?? String(localized: isSupplication ? "Supplications" : "Hadith"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let detail {
                    HadithBookmarkButton(narration: detail.narration, failed: $bookmarkFailed)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let detail {
                    HadithActions(textSizePresented: $textSizePresented, narration: detail.narration, translationLanguages: translationLanguages)
                        .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
                }
            }
        }
        .onChange(of: translation) { _, _ in translationChanged = true }
        .alert("Unable to save bookmark", isPresented: $bookmarkFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try again.") }
        .onDisappear {
            if !loading {
                session?.state.detailOffset = offset
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !loading {
                session?.state.detailOffset = offset
            }
        }
        .task(id: "\(currentID ?? initialID)-\(retry)-\(translation)-\(translationChanged)-\(locale.identifier)") {
            if highlight?.block == "english" || highlight?.block == "englishNarrator" {
                showEnglish = true
            }
            loading = true
            failed = false
            detail = nil
            do {
                var highlightedTranslation: String?
                if !translationChanged, let block = highlight?.block, block.hasPrefix("translation:") {
                    highlightedTranslation = String(block.dropFirst("translation:".count))
                }
                let loaded = try await reader.detail(id: currentID ?? initialID, query: query, orderedFallback: orderedFallback,
                                                     translation: highlightedTranslation ?? translation, languages: [locale.identifier])
                if loaded.narration.isSupplication {
                    translationLanguages = try await reader.translationLanguages()
                }
                try Task.checkCancellation()
                if session?.state.selection != loaded.narration.source {
                    session?.state.detailOffset = 0
                }
                session?.state.selection = loaded.narration.source
                detail = loaded
                loading = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                assets?.invalidateValidation()
                failed = true
                loading = false
            }
        }
    }

    private func highlighted(_ text: AttributedString, block: String, narration: Hadith, arabic: Bool = false) -> some View {
        HighlightText(text: HighlightTextContent.canonical(text), source: narration.source?.key ?? "", block: block,
                      isHadith: true, reference: HadithShareContent(narration: narration, showEnglish: showEnglish, locale: locale).reference,
                      arabic: arabic, markdown: text, focusWholeItem: narration.arabic.isEmpty && (block == "englishNarrator" || narration.englishNarrator.isEmpty))
    }

    @ViewBuilder private func metadata(_ title: LocalizedStringKey, value: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: value)
        }
    }
}
