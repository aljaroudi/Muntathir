import SwiftUI

struct HadithDownloadsSection: View {
    @Bindable var assets: HadithAssetStore
    let title: LocalizedStringKey
    @Environment(\.locale) private var locale
    @State private var removal: String?
    @State private var confirming = false

    var body: some View {
        Section {
            if assets.hasLocalAsset {
                LabeledContent {
                    AssetSizeText(bytes: assets.installedBytes)
                } label: { Label("Downloaded", systemImage: "checkmark.circle") }
            }
            if assets.isDownloading {
                AssetDownloadProgress(progress: assets.downloadProgress, installing: assets.state == .installing,
                                      preparing: assets.preparingDownload, remaining: assets.estimatedRemaining)
            } else if assets.state == .checking || assets.busy {
                ProgressView()
            } else if assets.state == .failed || assets.state == .incompatible {
                Text("Unable to download. Please try again.").foregroundStyle(.secondary)
                AssetDownloadButton(pack: assets.packID, retry: true) { Task { await assets.download() } }
            } else if !assets.hasLocalAsset {
                AssetDownloadButton(pack: assets.packID) { Task { await assets.download() } }
                    .accessibilityIdentifier("downloads-get-\(assets.packID)")
            }
            ForEach(assets.books) { book in
                HStack {
                    Text(book.title(locale: locale))
                    Spacer()
                    if book.installed {
                        Button("Remove download", systemImage: "trash", role: .destructive) {
                            removal = book.id
                            confirming = true
                        }
                        .accessibilityLabel(Text("Remove \(book.title(locale: locale))"))
                        .accessibilityIdentifier("downloads-remove-book-\(book.id)")
                    } else {
                        Button("Download", systemImage: "arrow.down.circle") {
                            Task { await assets.download(title: book.id) }
                        }
                        .accessibilityLabel(Text("Download \(book.title(locale: locale))"))
                        .accessibilityIdentifier("downloads-get-book-\(book.id)")
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(assets.busy || assets.isDownloading)
            }
            if assets.hasLocalAsset {
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    removal = nil
                    confirming = true
                }
                .disabled(assets.busy || assets.isDownloading)
                .accessibilityIdentifier("downloads-remove-\(assets.packID)")
            }
        } header: { Text(title) } footer: {
            if assets.books.contains(where: { !$0.installed }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restoring a book downloads the full library temporarily. Only your selected books are kept.")
                    if let bytes = AssetDownloadSize.bytes(for: assets.packID) {
                        AssetSizeText(bytes: bytes)
                    }
                }
            }
        }
        .confirmationDialog("Remove downloaded content?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove download", role: .destructive) {
                let title = removal
                Task {
                    if let title {
                        await assets.remove(title: title)
                    } else {
                        await assets.remove()
                    }
                }
            }
        } message: { Text("You can download it again later.") }
        .alert("Unable to finish storage cleanup", isPresented: $assets.storageError) {
            Button("Try again") { Task { await assets.refresh() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(assets.storageErrorMessage)
        }
    }
}
