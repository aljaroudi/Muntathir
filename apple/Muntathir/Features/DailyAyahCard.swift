import SwiftUI

struct DailyAyahCard: View {
    let ayah: Ayah
    var skyBackground = false
    @Environment(\.locale) private var locale
    @State private var sharedImage: SharedAyah?
    @State private var shareFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Daily ayah", systemImage: "book.closed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Share verse", systemImage: "square.and.arrow.up") {
                    if let image = AyahImageRenderer.image(for: ayah, locale: locale) {
                        sharedImage = SharedAyah(image: image)
                    } else {
                        shareFailed = true
                    }
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("share-daily-ayah")
            }
            AyahText(ayah: ayah)
                .textSelection(.enabled)
            if let english = ayah.english {
                Text(english)
                    .font(.body)
                    .environment(\.layoutDirection, .leftToRight)
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
        .sheet(item: $sharedImage) { item in
            AyahShareSheet(image: item.image)
        }
        .alert("Unable to create image", isPresented: $shareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try sharing the verse again.")
        }
    }
}

private struct AyahText: View {
    let ayah: Ayah
    var body: some View {
        Text(ayah.text)
            .font(.custom("KFGQPCHAFSUthmanicScript-Regula", size: 28, relativeTo: .title2))
            .lineSpacing(12)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityIdentifier("daily-ayah-text")
    }
}

struct AyahShareArtwork: View {
    let ayah: Ayah
    var body: some View {
        VStack(spacing: 28) {
            Label("Daily ayah", systemImage: "book.closed")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            AyahText(ayah: ayah)
                .padding()
            Text(ayah.id).font(.subheadline.monospacedDigit())
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
    static func image(for ayah: Ayah, locale: Locale) -> UIImage? {
        let content = AyahShareArtwork(ayah: ayah)
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

private struct SharedAyah: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct AyahShareSheet: UIViewControllerRepresentable {
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
