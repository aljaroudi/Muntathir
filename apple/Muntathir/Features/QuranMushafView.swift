import SwiftUI
import UIKit

struct QuranMushafView: View {
    @Environment(\.locale) private var locale
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
    @State private var pages: [Int: QuranPage] = [:]
    @State private var selected: Ayah?

    var body: some View {
        Group {
            if initialized {
                GeometryReader { viewport in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            // Reverse page order without reversing the scroll position's coordinate system.
                            ForEach((1 ... QuranPage.count).reversed(), id: \.self) { number in
                                QuranPageView(number: number, reader: reader, revision: translationStore.revision, surahs: surahs, selected: selected?.id) { page in
                                    pages[number] = page
                                    if number == current {
                                        reportPosition(page)
                                    }
                                } select: { selected = $0; positionChanged($0.surah, $0.number) }
                                    .environment(\.layoutDirection, .rightToLeft)
                                    .frame(width: viewport.size.width, height: viewport.size.height)
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
            if let highlight, let reference = try? QuranSearchText.reference(highlight.source),
               let ayah = try? await reader.verses(references: ["\(reference.surah):\(reference.verse)"]).first
            {
                selected = ayah
            }
        }
        .onChange(of: current) {
            if let current, let page = pages[current] {
                reportPosition(page)
            }
        }
    }

    private func reportPosition(_ page: QuranPage) {
        if let verse = page.verses.min(by: { $0.key < $1.key })?.value {
            positionChanged(verse.surah, verse.number)
        }
    }

    private var title: String {
        guard let current, let page = pages[current] else { return surah.title(locale: locale) }
        let name = surahs.first { $0.id == page.surah }?.title(locale: locale) ?? surah.title(locale: locale)
        return "\(name) · " + String(localized: "Juz \(page.juz)")
    }
}

private struct QuranPageView: View {
    let number: Int
    let reader: QuranReader
    let revision: Int
    let surahs: [QuranSurah]
    let selected: String?
    let loaded: (QuranPage) -> Void
    let select: (Ayah) -> Void
    @Environment(\.quranUserStore) private var store
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @State private var page: QuranPage?
    @State private var referenceLineWidth: CGFloat = 0
    @State private var failed = false
    @State private var retry = 0

    static let font = "KFGQPCHAFSUthmanicScript-Regula"
    static let referenceFontSize: CGFloat = 100
    static let basmala = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"

    var body: some View {
        Group {
            if let page {
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width - 32)
                    let lineHeight = max(1, (geometry.size.height - 56) / 15)
                    let size = fontSize(width: width, lineHeight: lineHeight)
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(page.lines) { line in
                                row(line, page: page, size: size, width: width)
                                    .frame(width: width, height: lineHeight)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        footer(page)
                    }
                    .padding(.horizontal, 16)
                }
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
                referenceLineWidth = measureLineWidth(loaded)
                page = loaded
                self.loaded(loaded)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                page = nil
                failed = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quran-page-\(number)")
    }

    @ViewBuilder private func row(_ line: QuranPage.Line, page: QuranPage, size: CGFloat, width _: CGFloat) -> some View {
        switch line.kind {
        case .surahName:
            let name = surahs.first { $0.id == line.surah }?.arabic ?? ""
            Text(verbatim: "سُورَةُ " + name)
                .font(.custom(Self.font, fixedSize: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, lineWidth: 1).padding(.vertical, 2))
                .accessibilityAddTraits(.isHeader)
        case .basmallah:
            Text(verbatim: Self.basmala).font(.custom(Self.font, fixedSize: size))
        case .ayah:
            JustifiedLine(justified: !line.centered, spacing: size * 0.25) {
                ForEach(line.words) { word in
                    wordView(word, page: page, size: size)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func wordView(_ word: QuranPage.Word, page: QuranPage, size: CGFloat) -> some View {
        let ayah = page.verses[word.index]
        let color = ayah.flatMap { store?.highlights(for: $0.id).max { $0.modifiedAt < $1.modifiedAt }?.color.color }
        return Group {
            if let ayah {
                VerseActionHost(ayah: ayah, translation: nil) {
                    wordButton(word, ayah: ayah, color: color, size: size)
                }
            }
        }
    }

    private func wordButton(_ word: QuranPage.Word, ayah: Ayah, color: Color?, size: CGFloat) -> some View {
        Button {
            select(ayah)
        } label: {
            Text(verbatim: word.text)
                .font(.custom(Self.font, fixedSize: size))
                .foregroundStyle(.primary)
                .fixedSize()
                .background(ayah.id == selected ? Color.accentColor.opacity(0.25) : color?.opacity(0.3) ?? .clear)
                .underline(differentiate && color != nil)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Verse \(ayah.id)"))
        .accessibilityIdentifier(word.word == 1 ? "quran-verse-\(ayah.id)" : "")
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

    /// The largest size at which the widest justified line still fits.
    private func fontSize(width: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let fit = referenceLineWidth > 0 ? Self.referenceFontSize * width / referenceLineWidth : lineHeight * 0.55
        return min(fit, lineHeight * 0.6)
    }

    private func measureLineWidth(_ page: QuranPage) -> CGFloat {
        let font = UIFont(name: Self.font, size: Self.referenceFontSize) ?? .systemFont(ofSize: Self.referenceFontSize)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        return page.lines.filter { $0.kind == .ayah }.map { line in
            let gap = line.centered ? Self.referenceFontSize * 0.25 : space
            return line.words.reduce(0) { $0 + ($1.text as NSString).size(withAttributes: [.font: font]).width } + gap * CGFloat(max(0, line.words.count - 1))
        }.max() ?? 0
    }
}

/// Lays words out right to left, spreading the leftover width between them unless centered.
private struct JustifiedLine: Layout {
    let justified: Bool
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = sizes.reduce(0) { $0 + $1.width }
        let gap = justified && subviews.count > 1 ? max(0, bounds.width - total) / CGFloat(subviews.count - 1) : spacing
        let used = total + gap * CGFloat(max(0, subviews.count - 1))
        var x = justified ? bounds.maxX : bounds.midX + used / 2
        for (subview, size) in zip(subviews, sizes) {
            x -= size.width
            subview.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(size))
            x -= gap
        }
    }
}
