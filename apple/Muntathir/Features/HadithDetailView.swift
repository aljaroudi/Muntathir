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

    @AppStorage("supplicationTranslation.v2") private var translation = "auto"
    @State private var translationLanguages: [String] = []
    @State private var translationChanged = false
    @AppStorage("hadithEnglishEnabled.v2") private var showEnglish = SupplicationTranslation.prefersEnglish()
    @Environment(\.locale) private var locale
    @State private var currentID: Int?
    @State private var detail: HadithDetail?
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    @State private var translationTarget: Locale.Language?

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
                        DictionarySelectableText(text: narration.chapter.chapterTitle(locale: locale), arabic: false)
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("supplication-title")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            DictionarySelectableText(text: narration.chapter.bookTitle(locale: locale), arabic: false)
                                .font(.headline)
                                .accessibilityIdentifier("hadith-detail-book")
                            if !detail.authorName(locale: locale).isEmpty {
                                DictionarySelectableText(text: detail.authorName(locale: locale), arabic: false)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("hadith-detail-author")
                            }
                            if !narration.chapter.chapterTitle(locale: locale).isEmpty {
                                DictionarySelectableText(text: narration.chapter.chapterTitle(locale: locale), arabic: false)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("hadith-detail-chapter")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        if !narration.arabic.isEmpty {
                            highlighted(narration.arabicDisplay, block: "arabic", narration: narration, arabic: true)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .accessibilityIdentifier("hadith-full-arabic")
                        }
                        if !isSupplication, showEnglish, !narration.englishNarrator.isEmpty || !narration.english.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                TranslationHeader(title: languageName("en"))
                                if !narration.englishNarrator.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Narrator").font(.subheadline).foregroundStyle(.secondary)
                                        highlighted(narration.narratorDisplay, block: "englishNarrator", narration: narration)
                                    }
                                    .accessibilityIdentifier("hadith-detail-narrator")
                                }
                                if !narration.english.isEmpty {
                                    highlighted(narration.englishDisplay, block: "english", narration: narration)
                                        .accessibilityIdentifier("hadith-full-english")
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                        }
                        if let translation = narration.translation {
                            VStack(alignment: .leading, spacing: 12) {
                                TranslationHeader(title: languageName(translation.language))
                                highlighted(HadithText.highlighted(translation.text, terms: QuranSearchText.queryTerms(query)), block: translation.block, narration: narration)
                                    .accessibilityIdentifier("supplication-full-translation")
                            }
                            .environment(\.layoutDirection, translation.isRightToLeft ? .rightToLeft : .leftToRight)
                        }
                        if !narration.arabic.isEmpty, let target = translationTarget,
                           !showsTrustedTranslation(in: target, narration: narration)
                        {
                            MachineTranslationSection(source: Self.arabic, target: target,
                                                      paragraphs: MachineTranslation.paragraphs(String(HadithText.markdown(narration.arabic).characters)))
                                .id(narration.id)
                        }
                    }
                    let gradings = detail.gradings.filter {
                        $0.status == "judgment" && !$0.judgment(locale: locale).isEmpty
                    }
                    if !gradings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Grading")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(gradings) { grading in
                                VStack(alignment: .leading, spacing: 4) {
                                    DictionarySelectableText(text: grading.judgment(locale: locale), arabic: false)
                                        .font(.headline)
                                    if !grading.grader(locale: locale).isEmpty {
                                        DictionarySelectableText(text: grading.grader(locale: locale), arabic: false)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !grading.reference(locale: locale).isEmpty {
                                        DictionarySelectableText(text: grading.reference(locale: locale), arabic: false)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    if !isSupplication {
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
            .readingColumn()
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .readingBackground()
        .onscreenEntity(HadithEntity.self, id: isSupplication ? nil : detail?.narration.source?.key)
        .onscreenEntity(SupplicationEntity.self, id: isSupplication ? detail?.narration.source?.key : nil)
        .trackReading(isSupplication ? .supplicationReading : .hadithReading, enabled: !loading && !failed && detail != nil && !textSizePresented)
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
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                if let detail {
                    HadithBookmarkButton(narration: detail.narration, failed: $bookmarkFailed)
                }
            }
            ToolbarItem(placement: .trailingBar) {
                if let detail {
                    HadithActions(textSizePresented: $textSizePresented, narration: detail.narration, translationLanguages: translationLanguages)
                        .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
                }
            }
        }
        .onChange(of: translation) { _, _ in translationChanged = true }
        .task(id: locale.identifier) {
            translationTarget = await MachineTranslation.supportedTarget(from: Self.arabic)
        }
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

    private static let arabic = Locale.Language(identifier: "ar")

    private func languageName(_ code: String) -> String {
        locale.localizedString(forLanguageCode: code) ?? code
    }

    /// A trusted translation already on screen in the machine translation's target makes it redundant.
    private func showsTrustedTranslation(in target: Locale.Language, narration: Hadith) -> Bool {
        if !isSupplication, showEnglish, !narration.english.isEmpty, target.languageCode == "en" {
            return true
        }
        guard let translation = narration.translation else { return false }
        return Locale.Language(identifier: translation.language).languageCode == target.languageCode
    }

    private func highlighted(_ text: AttributedString, block: String, narration: Hadith, arabic: Bool = false) -> some View {
        HighlightText(text: HighlightTextContent.canonical(text), source: narration.source?.key ?? "", block: block,
                      isHadith: true, reference: HadithShareContent(narration: narration, showEnglish: showEnglish, locale: locale).reference,
                      arabic: arabic, markdown: text, focusWholeItem: narration.arabic.isEmpty && (block == "englishNarrator" || narration.englishNarrator.isEmpty))
    }
}
