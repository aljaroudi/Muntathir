import SwiftUI

struct HadithLibraryView: View {
    @Bindable var assets: HadithAssetStore
    var supplications = false
    @Environment(\.hadithSession) private var session
    @State private var operation: Task<Void, Never>?

    var body: some View {
        if assets.state == .ready {
            Group {
                if supplications {
                    SupplicationsView(reader: assets.reader)
                } else {
                    HadithView(reader: assets.reader)
                }
            }
            .id([assets.revision, session?.generation ?? 0])
        } else {
            ContentUnavailableView {
                Label(LocalizedStringKey(supplications ? "Supplications" : "Hadith"), systemImage: "books.vertical")
            } description: {
                switch assets.state {
                case .checking:
                    if supplications {
                        Text("Checking supplications download…")
                    } else {
                        Text("Checking Hadith download…")
                    }
                case .downloading, .installing:
                    EmptyView()
                case .failed:
                    if supplications {
                        Text("Unable to download supplications. Check your connection and try again.")
                    } else {
                        Text("Unable to download Hadith. Check your connection and try again.")
                    }
                case .incompatible:
                    Text("This download needs an update.")
                default:
                    if supplications {
                        Text("Read and search supplications offline.")
                    } else {
                        Text("Read and search Hadith offline.")
                    }
                }
            } actions: {
                if assets.isDownloading {
                    AssetDownloadProgress(progress: assets.downloadProgress, installing: assets.state == .installing,
                                          preparing: assets.preparingDownload, remaining: assets.estimatedRemaining)
                        .frame(maxWidth: 300)
                } else if assets.state == .checking {
                    ProgressView()
                } else {
                    AssetDownloadButton(pack: assets.packID, retry: assets.state != .missing) {
                        operation = Task { await assets.download() }
                    }
                    .disabled(assets.busy)
                    .accessibilityIdentifier(supplications ? "supplications-download" : "hadith-download")
                }
            }
            .navigationTitle(LocalizedStringKey(supplications ? "Supplications" : "Hadith"))
            .alert("Unable to finish storage cleanup", isPresented: $assets.storageError) {
                Button("OK", role: .cancel) {}
            } message: { Text(assets.storageErrorMessage) }
            .splitFallbackStack()
        }
    }
}
