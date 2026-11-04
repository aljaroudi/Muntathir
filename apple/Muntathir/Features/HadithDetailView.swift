import SwiftUI

struct HadithDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hadithAssets) private var assets
    @Environment(\.hadithSession) private var session
    @State private var scrollPosition = ScrollPosition()
    @State private var offset: Double = 0
    let initialID: Int
    let reader: HadithReader
    let query: String
    let orderedFallback: Bool
    var highlight: ReadingHighlight?
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
                    ProgressView("Loading Hadith…")
                } else if failed {
                    HadithLoadError { Task { await assets?.refresh(); retry += 1 } }
                } else if let detail {
                    let narration = detail.narration
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
                        metadata("Hadith number", value: narration.number.formatted(.number.grouping(.never)))
                            .id("top")
                            .accessibilityIdentifier("hadith-detail-number")
                    }
                    .listRowBackground(HadithBookStyle.background(for: narration.collectionID))
                    Section {
                        if !narration.arabic.isEmpty {
                            highlighted(narration.arabicDisplay, block: "arabic", narration: narration, arabic: true)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .accessibilityIdentifier("hadith-full-arabic")
                        }
                        if showEnglish, !narration.englishNarrator.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Narrator").font(.subheadline).foregroundStyle(.secondary)
                                highlighted(narration.narratorDisplay, block: "englishNarrator", narration: narration)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .accessibilityIdentifier("hadith-detail-narrator")
                        }
                        if showEnglish, !narration.english.isEmpty {
                            highlighted(narration.englishDisplay, block: "english", narration: narration)
                                .environment(\.layoutDirection, .leftToRight)
                                .accessibilityIdentifier("hadith-full-english")
                        }
                    }
                    .listRowBackground(HadithBookStyle.background(for: narration.collectionID))
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
            .readingColumn()
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .background {
            if let detail {
                HadithBookStyle.background(for: detail.narration.collectionID).ignoresSafeArea()
            }
        }
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
        .navigationTitle("Hadith")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let detail {
                    HadithHighlightButton(narration: detail.narration)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let detail {
                    HadithActions(narration: detail.narration)
                }
            }
        }
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
        .task(id: "\(currentID ?? initialID)-\(retry)") {
            if highlight?.block == "english" || highlight?.block == "englishNarrator" {
                showEnglish = true
            }
            loading = true
            failed = false
            detail = nil
            do {
                let loaded = try await reader.detail(id: currentID ?? initialID, query: query, orderedFallback: orderedFallback)
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
