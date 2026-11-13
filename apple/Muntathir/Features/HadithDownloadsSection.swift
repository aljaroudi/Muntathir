import SwiftUI

struct HadithDownloadsSection: View {
    @Bindable var assets: HadithAssetStore
    let title: LocalizedStringKey
    @Environment(\.locale) private var locale
    @State private var booksExpanded = false
    @State private var requestedBook: String?

    var body: some View {
        Section {
            if !booksExpanded || requestedBook == nil {
                downloadStatus
            }
            if assets.hasLocalAsset {
                LabeledContent {
                    AssetSizeText(bytes: assets.installedBytes)
                } label: { Text("Total size") }
                .accessibilityIdentifier("downloads-size-\(assets.packID)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Remove download", systemImage: "trash", role: .destructive) {
                        Task { await assets.remove() }
                    }
                    .accessibilityIdentifier("downloads-remove-\(assets.packID)")
                    .disabled(assets.busy || assets.isDownloading)
                }
            }
            if !assets.isDownloading, assets.state == .checking || assets.busy {
                ProgressView()
            } else if requestedBook == nil, assets.state == .failed || assets.state == .incompatible {
                AssetDownloadButton(pack: assets.packID, retry: true) { Task { await assets.download() } }
            } else if !assets.isDownloading, !assets.hasLocalAsset {
                AssetDownloadButton(pack: assets.packID) { Task { await assets.download() } }
                    .accessibilityIdentifier("downloads-get-\(assets.packID)")
            }
            if !assets.books.isEmpty {
                DisclosureGroup("Books", isExpanded: $booksExpanded) {
                    ForEach(assets.books) { book in
                        let showsProgress = requestedBook == book.id && assets.isDownloading
                        let retry = requestedBook == book.id && (assets.state == .failed || assets.state == .incompatible)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(book.title(locale: locale))
                                Spacer()
                                if book.installed {
                                    if let bytes = book.estimatedBytes {
                                        AssetSizeText(bytes: bytes, isEstimated: true)
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                } else if !showsProgress {
                                    Button(retry ? "Try again" : "Download", systemImage: retry ? "arrow.clockwise" : "arrow.down.circle") {
                                        requestedBook = book.id
                                        Task { await assets.download(title: book.id) }
                                    }
                                    .accessibilityLabel(retry ? Text("Try again") : Text("Download \(book.title(locale: locale))"))
                                    .accessibilityIdentifier("downloads-get-book-\(book.id)")
                                    .disabled(assets.busy || assets.isDownloading)
                                }
                            }
                            if requestedBook == book.id {
                                downloadStatus
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if book.installed {
                                Button("Remove download", systemImage: "trash", role: .destructive) {
                                    Task { await assets.remove(title: book.id) }
                                }
                                .accessibilityIdentifier("downloads-remove-book-\(book.id)")
                                .disabled(assets.busy || assets.isDownloading)
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                    if assets.books.contains(where: { !$0.installed }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Restoring a book downloads the full library temporarily. Only your selected books are kept.")
                            if let bytes = AssetDownloadSize.bytes(for: assets.packID) {
                                AssetSizeText(bytes: bytes)
                            }
                        }
                    }
                }
            }
        } header: { Text(title) }
        .onChange(of: assets.state) { _, state in
            if state == .ready || state == .missing {
                requestedBook = nil
            }
        }
        .alert("Unable to finish storage cleanup", isPresented: $assets.storageError) {
            Button("Try again") { Task { await assets.refresh() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(assets.storageErrorMessage)
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        if assets.isDownloading {
            AssetDownloadProgress(progress: assets.downloadProgress, installing: assets.state == .installing,
                                  preparing: assets.preparingDownload, remaining: assets.estimatedRemaining)
        } else if assets.state == .failed || assets.state == .incompatible {
            Text("Unable to download. Please try again.").foregroundStyle(.secondary)
        }
    }
}
