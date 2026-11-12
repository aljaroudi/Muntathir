import SwiftUI

struct QuranMushafView: View {
    @Environment(\.locale) private var locale
    @Environment(\.isSearching) private var isSearching
    @State private var readingViewport: CGSize?
    let surah: QuranSurah
    var initialVerse = 1
    let reader: QuranReader
    var highlight: ReadingHighlight?
    var positionChanged: (Int, Int) -> Void = { _, _ in }
    @State private var translationStore = QuranTranslationStore.shared
    @State private var surahs: [QuranSurah] = []
    @State private var initializationFailed = false
    @State private var initializationRetry = 0
    @State private var initialized = false
    @State private var current: Int?
    @State private var visiblePage: QuranPage?
    @State private var reportedInitialPage = false

    var body: some View {
        Group {
            if initialized {
                GeometryReader { viewport in
                    let height = isSearching ? (readingViewport?.height ?? viewport.size.height) : viewport.size.height
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            // Reverse page order without reversing the scroll position's coordinate system.
                            ForEach((1 ... QuranPage.count).reversed(), id: \.self) { number in
                                QuranPageView(number: number, reader: reader, revision: translationStore.revision, surahs: surahs, highlight: highlight, active: number == current) { page in
                                    if number == current {
                                        visiblePage = page
                                        reportPosition(page)
                                    }
                                } select: { positionChanged($0.surah, $0.number) }
                                    .environment(\.layoutDirection, .rightToLeft)
                                    .frame(width: viewport.size.width, height: height)
                                    .id(number)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                    .scrollPosition(id: $current, anchor: .center)
                    .scrollIndicators(.hidden)
                    .environment(\.layoutDirection, .leftToRight)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    // Search moves native toolbar space; retain the reading layout while typing.
                    if !isSearching || readingViewport?.width != size.width {
                        readingViewport = size
                    }
                }
            } else if initializationFailed {
                ContentUnavailableView {
                    Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Try again") { initializationRetry += 1 }
                }
            } else {
                ProgressView("Loading Quran…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .readingBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    QuranReadingModePicker()
                    QuranTranslationPicker()
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }.accessibilityIdentifier("quran-reading-options")
            }
        }
        .task(id: initializationRetry) {
            guard !initialized else { return }
            if let block = highlight?.block, block != "arabic", translationStore.activeID != block {
                translationStore.select(block)
            }
            surahs = (try? QuranSurah.load()) ?? []
            initializationFailed = false
            do {
                guard let page = try await reader.page(surah: surah.id, verse: initialVerse) else {
                    initializationFailed = true
                    return
                }
                try Task.checkCancellation()
                current = page
                initialized = true
            } catch {
                guard !Task.isCancelled else { return }
                initializationFailed = true
                return
            }
        }
    }

    private func reportPosition(_ page: QuranPage) {
        if !reportedInitialPage {
            reportedInitialPage = true
            if let verse = page.verses.values.first(where: { $0.surah == surah.id && $0.number == initialVerse }) {
                positionChanged(verse.surah, verse.number)
                return
            }
        }
        if let verse = page.verses.min(by: { $0.key < $1.key })?.value {
            positionChanged(verse.surah, verse.number)
        }
    }

    private var title: String {
        guard let page = visiblePage else { return surah.title(locale: locale) }
        let name = surahs.first { $0.id == page.surah }?.title(locale: locale) ?? surah.title(locale: locale)
        return "\(name) · " + String(localized: "Juz \(page.juz)")
    }
}

private struct QuranPageView: View {
    @Environment(\.locale) private var locale
    let number: Int
    let reader: QuranReader
    let revision: Int
    let surahs: [QuranSurah]
    let highlight: ReadingHighlight?
    let active: Bool
    let loaded: (QuranPage) -> Void
    let select: (Ayah) -> Void
    @State private var page: QuranPage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let page {
                VStack(spacing: 0) {
                    QuranPageReader(page: page, surahs: surahs, highlight: highlight, select: select)
                    footer(page)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else if failed {
                ContentUnavailableView {
                    Label("Unable to load Quran", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Try again") { retry += 1 }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: "\(number)-\(revision)-\(retry)") {
            failed = false
            do {
                let loaded = try await reader.page(number)
                try Task.checkCancellation()
                page = loaded
                self.loaded(loaded)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                page = nil
                failed = true
            }
        }
        .onChange(of: active) { _, active in
            if active, let page {
                loaded(page)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quran-page-\(number)")
    }

    private func footer(_ page: QuranPage) -> some View {
        HStack {
            Text("Juz \(page.juz)")
            Spacer()
            if !page.sajdas.isEmpty {
                Image(systemName: "arrow.down.to.line").accessibilityLabel(Text("Prostration"))
            }
            Text(page.number, format: .number).monospacedDigit()
            Spacer()
            Text("Hizb \((page.hizbQuarter + 3) / 4)")
        }
        .font(.caption)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(.secondary)
        .frame(height: 40)
    }
}
