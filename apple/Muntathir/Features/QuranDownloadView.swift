import SwiftUI

struct QuranDownloadView: View {
    @State private var store = QuranTranslationStore.shared
    @Environment(\.dismiss) private var dismiss
    var requested: String?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Quran translations", systemImage: "character.bubble")
            } description: {
                if store.downloadState == .failed {
                    Text("Unable to download. Please try again.")
                } else {
                    Text("Download translations to read offline.")
                }
            } actions: {
                if store.isDownloading {
                    AssetDownloadProgress(progress: store.downloadProgress, installing: store.downloadState == .installing)
                        .frame(maxWidth: 300)
                } else {
                    AssetDownloadButton(pack: "quran-translations", retry: store.downloadState == .failed) {
                        Task { await store.download(requested: requested) }
                    }
                    .disabled(store.busy)
                    .accessibilityIdentifier("quran-download")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: store.revision) {
            if let requested, store.isInstalled(requested) {
                dismiss()
            }
        }
    }
}
