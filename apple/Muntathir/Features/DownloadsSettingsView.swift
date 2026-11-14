import SwiftUI

struct DownloadsSettingsView: View {
    @Environment(\.rulingsAssets) private var rulings
    @Environment(\.supplicationAssets) private var supplications
    @Environment(\.hadithAssets) private var hadith
    @Environment(\.locale) private var locale
    @State private var quran = QuranTranslationStore.shared
    @State private var requestedTranslation: String?

    var body: some View {
        List {
            if let rulings { RulingsDownloadSection(assets: rulings) }
            if let hadith {
                HadithDownloadsSection(assets: hadith, title: "Hadith")
            }
            if let supplications {
                HadithDownloadsSection(assets: supplications, title: "Supplications")
            }
            Section {
                if requestedTranslation == nil {
                    translationDownloadStatus
                }
                if !quran.installedSizes.isEmpty {
                    LabeledContent {
                        AssetSizeText(bytes: quran.installedSizes.values.reduce(0, +))
                    } label: { Text("Total size") }
                        .accessibilityIdentifier("downloads-size-translations")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove all translations", systemImage: "trash", role: .destructive) {
                                Task { await quran.remove(QuranTranslation.downloadable.map(\.id)) }
                            }
                            .accessibilityIdentifier("downloads-remove-translations")
                            .disabled(quran.busy || quran.isDownloading)
                        }
                }
                LabeledContent("English", value: String(localized: "Included"))
                    .accessibilityIdentifier("downloads-bundled-en")
                ForEach(QuranTranslation.downloadable) { translation in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(locale.localizedString(forIdentifier: translation.language) ?? translation.language)
                            Spacer()
                            if let size = quran.installedSizes[translation.id] {
                                AssetSizeText(bytes: size).foregroundStyle(.secondary)
                            } else if requestedTranslation != translation.id || !quran.isDownloading {
                                Button(quran.downloadState == .failed ? LocalizedStringKey("Try again") : LocalizedStringKey("Download"), systemImage: "arrow.down.circle") {
                                    requestedTranslation = translation.id
                                    Task { await quran.download(requested: translation.id) }
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("downloads-get-\(translation.id)")
                                .disabled(quran.busy || quran.isDownloading)
                            }
                        }
                        if requestedTranslation == translation.id {
                            translationDownloadStatus
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if quran.installedSizes[translation.id] != nil {
                            Button("Remove download", systemImage: "trash", role: .destructive) {
                                Task { await quran.remove([translation.id]) }
                            }
                            .accessibilityIdentifier("downloads-remove-\(translation.id)")
                            .disabled(quran.busy || quran.isDownloading)
                        }
                    }
                }
            } header: { Text("Quran translations") }
        }
        .navigationTitle("Downloads")
        .task { await quran.refresh() }
        .onChange(of: quran.downloadState) { _, state in
            if state == .idle {
                requestedTranslation = nil
            }
        }
        .alert("Unable to finish storage cleanup", isPresented: $quran.storageError) {
            Button("Try again") { Task { await quran.refresh() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some files remain on this device. Please try again.")
        }
    }

    @ViewBuilder private var translationDownloadStatus: some View {
        if quran.isDownloading {
            AssetDownloadProgress(progress: quran.downloadProgress, installing: quran.downloadState == .installing,
                                  preparing: quran.preparingDownload)
        } else if quran.downloadState == .failed {
            Text("Unable to download. Please try again.").foregroundStyle(.secondary)
        }
    }
}
