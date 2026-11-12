import SwiftUI

struct DownloadsSettingsView: View {
    @Environment(\.supplicationAssets) private var supplications
    @Environment(\.hadithAssets) private var hadith
    @Environment(\.locale) private var locale
    @State private var quran = QuranTranslationStore.shared
    @State private var removal: Removal?

    private enum Removal: Identifiable {
        case translations, language(String), hadith, supplications
        var id: String {
            switch self {
            case .translations: "translations"
            case .hadith: "hadith"
            case .supplications: "supplications"
            case let .language(id): id
            }
        }
    }

    var body: some View {
        List {
            if let hadith {
                HadithDownloadsSection(assets: hadith, title: "Hadith")
            }
            if let supplications {
                HadithDownloadsSection(assets: supplications, title: "Supplications")
            }
            Section {
                LabeledContent("English", value: String(localized: "Included"))
                    .accessibilityIdentifier("downloads-bundled-en")
                ForEach(QuranTranslation.downloadable) { translation in
                    HStack {
                        Text(locale.localizedString(forIdentifier: translation.language) ?? translation.language)
                        Spacer()
                        if let size = quran.installedSizes[translation.id] {
                            AssetSizeText(bytes: size).foregroundStyle(.secondary)
                        } else {
                            Button(quran.downloadState == .failed ? LocalizedStringKey("Try again") : LocalizedStringKey("Download"), systemImage: "arrow.down.circle") {
                                Task { await quran.download(requested: translation.id) }
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("downloads-get-\(translation.id)")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if quran.installedSizes[translation.id] != nil {
                            Button("Remove download", systemImage: "trash", role: .destructive) {
                                removal = .language(translation.id)
                            }
                            .accessibilityIdentifier("downloads-remove-\(translation.id)")
                            .disabled(quran.busy || quran.isDownloading)
                        }
                    }
                    .disabled(quran.busy || quran.isDownloading)
                }
                if quran.isDownloading {
                    AssetDownloadProgress(progress: quran.downloadProgress, installing: quran.downloadState == .installing)
                } else if quran.downloadState == .failed {
                    Text("Unable to download. Please try again.").foregroundStyle(.secondary)
                }
            } header: { Text("Quran translations") }
        }
        .navigationTitle("Downloads")
        .toolbar {
            Menu {
                if let hadith, hadith.hasLocalAsset {
                    Button("Remove Hadith downloads", systemImage: "trash", role: .destructive) { removal = .hadith }
                        .accessibilityIdentifier("downloads-remove-hadith")
                        .disabled(hadith.busy || hadith.isDownloading)
                }
                if let supplications, supplications.hasLocalAsset {
                    Button("Remove Supplication downloads", systemImage: "trash", role: .destructive) { removal = .supplications }
                        .disabled(supplications.busy || supplications.isDownloading)
                }
                if !quran.installedSizes.isEmpty {
                    Button("Remove all translations", systemImage: "trash", role: .destructive) { removal = .translations }
                        .disabled(quran.busy || quran.isDownloading)
                        .accessibilityIdentifier("downloads-remove-translations")
                }
            } label: {
                Label("Download actions", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("downloads-actions")
            .disabled(quran.installedSizes.isEmpty && hadith?.hasLocalAsset != true && supplications?.hasLocalAsset != true)
        }
        .task { await quran.refresh() }
        .confirmationDialog("Remove downloaded content?", isPresented: Binding(get: { removal != nil }, set: {
            if !$0 {
                removal = nil
            }
        }), titleVisibility: .visible) {
            if let removal {
                Button("Remove download", role: .destructive) {
                    Task {
                        switch removal {
                        case .hadith: await hadith?.remove()
                        case .supplications: await supplications?.remove()
                        case .translations: await quran.remove(QuranTranslation.downloadable.map(\.id))
                        case let .language(id): await quran.remove([id])
                        }
                    }
                }
            }
        } message: {
            Text("You can download it again later.")
        }
        .alert("Unable to finish storage cleanup", isPresented: $quran.storageError) {
            Button("Try again") { Task { await quran.refresh() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some files remain on this device. Please try again.")
        }
    }
}
