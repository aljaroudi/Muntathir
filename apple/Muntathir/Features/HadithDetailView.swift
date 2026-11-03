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
    @AppStorage("hadithEnglishEnabled") private var showEnglish = true
    @Environment(\.locale) private var locale
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
                            LabeledContent("Author", value: detail.authorName(locale: locale))
                                .accessibilityIdentifier("hadith-detail-author")
                        }
                        LabeledContent("Book", value: narration.chapter.bookTitle(locale: locale))
                            .accessibilityIdentifier("hadith-detail-book")
                        if !narration.chapter.chapterTitle(locale: locale).isEmpty {
                            LabeledContent("Chapter", value: narration.chapter.chapterTitle(locale: locale))
                                .accessibilityIdentifier("hadith-detail-chapter")
                        }
                        LabeledContent("Hadith number", value: narration.number, format: .number.grouping(.never))
                            .id("top")
                            .accessibilityIdentifier("hadith-detail-number")
                    }
                    .listRowBackground(HadithBookStyle.background(for: narration.collectionID))
                    Section {
                        if !narration.arabic.isEmpty {
                            HadithMarkdownView(text: narration.arabicDisplay)
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .accessibilityIdentifier("hadith-full-arabic")
                        }
                        if showEnglish, !narration.englishNarrator.isEmpty {
                            LabeledContent {
                                HadithMarkdownView(text: narration.narratorDisplay)
                                    .environment(\.layoutDirection, .leftToRight)
                            } label: {
                                Text("Narrator")
                            }
                            .accessibilityIdentifier("hadith-detail-narrator")
                        }
                        if showEnglish, !narration.english.isEmpty {
                            HadithMarkdownView(text: narration.englishDisplay)
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
            .padding()
        }
        .background {
            if let detail {
                HadithBookStyle.background(for: detail.narration.collectionID).ignoresSafeArea()
            }
        }
        .textSelection(.enabled)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Double.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, value in offset = value }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, !loading {
                session?.state.detailOffset = offset
            }
        }
        .onChange(of: loading) { _, loading in
            if !loading {
                scrollPosition.scrollTo(y: session?.state.detailOffset ?? 0)
            }
        }
        .navigationTitle("Hadith")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { HadithTranslationPicker() }
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
}
