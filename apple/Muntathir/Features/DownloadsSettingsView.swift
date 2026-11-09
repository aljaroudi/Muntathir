import SwiftUI

struct DownloadsSettingsView: View {
    @Environment(\.supplicationAssets) private var supplications
    @Environment(\.hadithAssets) private var hadith
    @Environment(\.locale) private var locale
    @State private var quran = QuranTranslationStore.shared
    @State private var removal: Removal?
    @State private var hadithRemovalFailed = false
    @State private var requested: QuranTranslation?

    private enum Removal: Identifiable {
        case hadith, supplications, translations, language(String)
        var id: String {
            switch self {
            case .hadith: "hadith"
            case .supplications: "supplications"
            case .translations: "translations"
            case let .language(id): id
            }
        }
    }

    var body: some View {
        List {
            if let hadith {
                Section("Hadith") {
                    if hadith.hasLocalAsset {
                        LabeledContent {
                            AssetSizeText(bytes: hadith.installedBytes)
                        } label: { Text("Hadith") }
                        Button("Remove download", systemImage: "trash", role: .destructive) { removal = .hadith }
                            .disabled(hadith.busy)
                            .accessibilityIdentifier("downloads-remove-hadith")
                    } else {
                        NavigationLink("Hadith") { HadithLibraryView(assets: hadith) }
                    }
                }
            }
            if let supplications {
                Section("Supplications") {
                    if supplications.hasLocalAsset {
                        LabeledContent {
                            AssetSizeText(bytes: supplications.installedBytes)
                        } label: { Text("Supplications") }
                        Button("Remove download", systemImage: "trash", role: .destructive) { removal = .supplications }
                            .disabled(supplications.busy)
                            .accessibilityIdentifier("downloads-remove-supplications")
                    } else {
                        NavigationLink("Supplications") {
                            HadithLibraryView(assets: supplications, supplications: true)
                                .environment(\.hadithAssets, supplications)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Arabic", value: String(localized: "Included"))
                    .accessibilityIdentifier("downloads-bundled-ar")
                LabeledContent("English", value: String(localized: "Included"))
                    .accessibilityIdentifier("downloads-bundled-en")
                ForEach(QuranTranslation.downloadable) { translation in
                    HStack {
                        Text(locale.localizedString(forIdentifier: translation.language) ?? translation.language)
                        Spacer()
                        if let size = quran.installedSizes[translation.id] {
                            AssetSizeText(bytes: size).foregroundStyle(.secondary)
                            Button("Remove download", systemImage: "trash", role: .destructive) {
                                removal = .language(translation.id)
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel(Text("Remove \(locale.localizedString(forIdentifier: translation.language) ?? translation.language)"))
                            .accessibilityIdentifier("downloads-remove-\(translation.id)")
                        } else {
                            Button("Download", systemImage: "arrow.down.circle") {
                                requested = translation
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("downloads-get-\(translation.id)")
                        }
                    }
                    .disabled(quran.busy || quran.isDownloading)
                }
                if quran.downloadState == .installing {
                    ProgressView("Preparing translations…")
                } else if quran.isDownloading {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ProgressView(value: quran.downloadProgress?.fractionCompleted ?? 0)
                            .accessibilityLabel("Downloading translations…")
                    }
                }
                if !quran.installedSizes.isEmpty {
                    Button("Remove all translations", systemImage: "trash", role: .destructive) { removal = .translations }
                        .disabled(quran.busy || quran.isDownloading)
                        .accessibilityIdentifier("downloads-remove-translations")
                }
            } header: { Text("Quran translations") }
        }
        .navigationTitle("Downloads")
        .task { await quran.refresh() }
        .sheet(item: $requested) { QuranDownloadView(requested: $0.id) }
        .confirmationDialog("Remove downloaded content?", isPresented: Binding(get: { removal != nil }, set: {
            if !$0 {
                removal = nil
            }
        }), titleVisibility: .visible) {
            if let removal {
                Button("Remove download", role: .destructive) {
                    Task {
                        switch removal {
                        case .hadith:
                            await hadith?.remove()
                            hadithRemovalFailed = hadith?.state != .missing
                        case .supplications:
                            await supplications?.remove()
                            hadithRemovalFailed = supplications?.state != .missing
                        case .translations: await quran.remove(QuranTranslation.downloadable.map(\.id))
                        case let .language(id): await quran.remove([id])
                        }
                    }
                }
            }
        } message: {
            Text("You can download it again later.")
        }
        .alert("Unable to remove download", isPresented: $hadithRemovalFailed) {
            Button("OK", role: .cancel) {}
        }
        .alert("Unable to finish storage cleanup", isPresented: $quran.storageError) {
            Button("Try again") { Task { await quran.refresh() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some files remain on this device. Please try again.")
        }
    }
}
