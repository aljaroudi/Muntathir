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
            AyahText(ayah: ayah, alignment: .center)
                .accessibilityIdentifier("daily-ayah-text")
                .textSelection(.enabled)
            if let translation = ayah.selectedTranslationText {
                Text(translation)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, dailyTranslation.map { Locale(identifier: $0.language).language.characterDirection == .rightToLeft } == true ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("daily-ayah-translation")
            }
            Text(ayah.id)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
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
    var body: some View {
        Text(ayah.text)
            .font(.custom("KFGQPCHAFSUthmanicScript-Regula", size: 28, relativeTo: .title2))
            .lineSpacing(12)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

struct AyahShareArtwork: View {
    let ayah: Ayah
    var translation: QuranTranslation?
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(spacing: 28) {
            Label("The Holy Quran", systemImage: "book.closed")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            AyahText(ayah: ayah)
                .padding()
            if let translation, let text = ayah.translations[translation.id] {
                Text(text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, Locale(identifier: translation.language).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                Text(translation.translator).font(.caption).foregroundStyle(.secondary)
            }
            Text(VerseShareContent(ayah: ayah, translation: translation, locale: locale).reference)
                .font(.subheadline.monospacedDigit())
            Divider().overlay(Color.accentColor.opacity(0.2))
            HStack {
                Text("Muntathir").font(.subheadline.weight(.medium))
            }.foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 540)
        .background { AyahBackground() }
        .clipped()
    }
}

@MainActor enum AyahImageRenderer {
    static func image(for ayah: Ayah, locale: Locale, translation: QuranTranslation? = nil) -> UIImage? {
        let content = AyahShareArtwork(ayah: ayah, translation: translation)
            .environment(\.locale, locale)
            .environment(\.layoutDirection, locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, .light)
            .dynamicTypeSize(.large)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

struct SharedAyah: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct AyahShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
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
