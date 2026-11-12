import SwiftUI

struct DailyAyahCard: View {
    let ayah: Ayah
    var skyBackground = false
    @Environment(\.locale) private var locale

    private var dailyTranslation: QuranTranslation? {
        guard ayah.selectedTranslationText != nil else { return nil }
        return QuranTranslation.catalog.first { ayah.translations[$0.id] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Daily ayah", systemImage: "book.closed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                VerseActions(ayah: ayah, translation: dailyTranslation, identifier: "share-daily-ayah")
            }
            HighlightText(text: ayah.text, source: ayah.id, block: "arabic", arabic: true, centered: true)
                .accessibilityIdentifier("daily-ayah-text")
                .textSelection(.enabled)
            if let translation = ayah.selectedTranslationText {
                HighlightText(text: translation, source: ayah.id, block: dailyTranslation?.id ?? "", centered: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, dailyTranslation.map { Locale(identifier: $0.language).language.characterDirection == .rightToLeft } == true ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("daily-ayah-translation")
            }
            Text(QuranReference.display(ayah.id, locale: locale))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .readingColumn()
        .padding(20)
        .background {
            if skyBackground {
                SkyCardSurface()
            } else {
                AyahBackground()
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

struct AyahText: View {
    let ayah: Ayah
    var alignment: TextAlignment = .leading
    var adjustable = true
    var body: some View {
        Text(ayah.text)
            .readingText(arabic: true, adjustable: adjustable)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

struct AyahShareArtwork: View {
    let ayah: Ayah
    var translation: QuranTranslation?
    var highlights: [ReadingHighlight] = []
    @Environment(\.locale) private var locale
    var body: some View {
        ShareArtwork(reference: VerseShareContent(ayah: ayah, translation: translation, locale: locale).imageReference) {
            ShareHighlightText(text: AttributedString(ayah.text), highlights: highlights, block: "arabic")
                .readingText(arabic: true, adjustable: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .rightToLeft)
                .padding()
            if let translation, let text = ayah.translations[translation.id] {
                ShareHighlightText(text: AttributedString(text), highlights: highlights, block: translation.id)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, Locale(identifier: translation.language).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            }
        }
    }
}

struct ShareArtwork<Content: View>: View {
    let reference: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 28) {
            content
            Text(reference).font(.subheadline.monospacedDigit())
            Divider().overlay(Color.accentColor.opacity(0.2))
            Text("Muntathir").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 540)
        .background { AyahBackground() }
    }
}

@MainActor enum ShareImageRenderer {
    static let width: CGFloat = 540
    static let maximumHeight: CGFloat = 960

    private static func prepared(_ artwork: some View, locale: Locale) -> some View {
        artwork.environment(\.locale, locale)
            .environment(\.layoutDirection, locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, .light)
            .dynamicTypeSize(.large)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func fits(height: CGFloat) -> Bool {
        height.isFinite && height > 0 && ceil(height) <= maximumHeight
    }

    static func canShare(_ artwork: some View, locale: Locale) -> Bool {
        let host = UIHostingController(rootView: prepared(artwork, locale: locale))
        return fits(height: host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    static func image(_ artwork: some View, locale: Locale) -> UIImage? {
        guard canShare(artwork, locale: locale) else { return nil }
        let renderer = ImageRenderer(content: prepared(artwork, locale: locale))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.uiImage, image.size.height * image.scale <= 1920 else { return nil }
        return image
    }
}

@MainActor enum AyahImageRenderer {
    static func canShare(_ ayah: Ayah, locale: Locale, translation: QuranTranslation? = nil, highlights: [ReadingHighlight] = []) -> Bool {
        ShareImageRenderer.canShare(AyahShareArtwork(ayah: ayah, translation: translation, highlights: highlights), locale: locale)
    }

    static func image(for ayah: Ayah, locale: Locale, translation: QuranTranslation? = nil, highlights: [ReadingHighlight] = []) -> UIImage? {
        ShareImageRenderer.image(AyahShareArtwork(ayah: ayah, translation: translation, highlights: highlights), locale: locale)
    }
}

struct SharedAyah: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct AyahShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    init(items: [Any]) {
        self.items = items
    }

    init(image: UIImage) {
        self.init(items: [image])
    }

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

#if DEBUG
    let exampleAyah = Ayah(
        surah: 26,
        number: 114,
        text: "وَمَآ أَنَا۠ بِطَارِدِ ٱلْمُؤْمِنِينَ"
    )

    #Preview("Daily ayah") {
        DailyAyahCard(ayah: exampleAyah)
            .padding()
    }

    #Preview("Daily ayah — dark Arabic") {
        DailyAyahCard(ayah: exampleAyah)
            .padding().preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "ar"))
            .environment(\.layoutDirection, .rightToLeft)
    }

    #Preview("Shared image") {
        AyahShareArtwork(ayah: exampleAyah)
    }
#endif
