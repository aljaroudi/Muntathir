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
    @State private var current: Int?
    @State private var pages: [Int: QuranPage] = [:]
    @State private var selected: Ayah?
    @State private var jumpPresented = false
    @State private var jumpText = ""
    @State private var invalidJump = false

    var body: some View {
        Group {
            if let current {
                TabView(selection: Binding(get: { current }, set: { self.current = $0 })) {
                    ForEach(1 ... QuranPage.count, id: \.self) { number in
                        QuranPageView(number: number, reader: reader, revision: translationStore.revision, surahs: surahs, selected: selected?.id) { page in
                            pages[number] = page
                            if number == current {
                                reportPosition(page)
                            }
                        } select: { selected = $0; positionChanged($0.surah, $0.number) }
                            .tag(number)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environment(\.layoutDirection, .rightToLeft)
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
                Button("Go to page or verse", systemImage: "number") { jumpPresented = true }
                    .accessibilityIdentifier("quran-jump")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    QuranReadingModePicker()
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }.accessibilityIdentifier("quran-reading-options")
            }
        }
        .alert("Go to page or verse", isPresented: $jumpPresented) {
            TextField("Page or 2:255", text: $jumpText).keyboardType(.numbersAndPunctuation)
            Button("Go") { Task { await jump() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a page from \(1, format: .number) to \(QuranPage.count, format: .number), or a verse such as 2:255.")
        }
        .alert("Invalid page or verse", isPresented: $invalidJump) {
            Button("OK", role: .cancel) {}
        }
        .task(id: initializationRetry) {
            guard current == nil else { return }
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

    private func jump() async {
        let text = jumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        jumpText = ""
        if let reference = try? QuranSearchText.reference(text) {
            if let page = try? await reader.page(surah: reference.surah, verse: reference.verse) {
                current = page
                return
            }
        } else if let number = QuranSearchText.number(text), (1 ... QuranPage.count).contains(number) {
            current = number
            return
        }
        invalidJump = true
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
    @State private var failed = false
    @State private var retry = 0

    static let font = "KFGQPCHAFSUthmanicScript-Regula"
    static let basmala = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"

    var body: some View {
        Group {
            if let page {
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width - 32)
                    let lineHeight = max(1, (geometry.size.height - 56) / 15)
                    let size = fontSize(page, width: width, lineHeight: lineHeight)
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
            JustifiedLine(justified: !line.centered) {
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
    private func fontSize(_ page: QuranPage, width: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let reference: CGFloat = 100
        let font = UIFont(name: Self.font, size: reference) ?? .systemFont(ofSize: reference)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let widest = page.lines.filter { $0.kind == .ayah }.map { line in
            line.words.reduce(0) { $0 + ($1.text as NSString).size(withAttributes: [.font: font]).width } + space * CGFloat(max(0, line.words.count - 1))
        }.max() ?? 0
        let fit = widest > 0 ? reference * width / widest : lineHeight * 0.55
        return min(fit, lineHeight * 0.6)
    }
}

/// Lays words out right to left, spreading the leftover width between them unless centered.
private struct JustifiedLine: Layout {
    let justified: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = sizes.reduce(0) { $0 + $1.width }
        let natural = sizes.first.map { $0.height * 0.25 } ?? 0
        let gap = justified && subviews.count > 1 ? max(0, bounds.width - total) / CGFloat(subviews.count - 1) : natural
        let used = total + gap * CGFloat(max(0, subviews.count - 1))
        var x = justified ? bounds.maxX : bounds.midX + used / 2
        for (subview, size) in zip(subviews, sizes) {
            x -= size.width
            subview.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(size))
            x -= gap
        }
    }
}
