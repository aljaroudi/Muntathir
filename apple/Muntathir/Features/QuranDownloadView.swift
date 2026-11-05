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
                    VStack(spacing: 8) {
                        if store.downloadState == .installing {
                            ProgressView("Preparing translations…")
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                ProgressView(value: store.downloadProgress?.fractionCompleted ?? 0)
                                    .accessibilityLabel("Downloading translations…")
                            }
                        }
                    }
                    .frame(maxWidth: 240)
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
