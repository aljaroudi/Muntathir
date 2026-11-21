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
            if let rulings {
                RulingsDownloadSection(assets: rulings)
            }
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
                        .removeDownloadControl("Remove all translations", id: "downloads-remove-translations",
                                               disabled: quran.busy || quran.isDownloading)
                        {
                            Task { await quran.remove(QuranTranslation.downloadable.map(\.id)) }
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
                    .removeDownloadControl("Remove download", id: "downloads-remove-\(translation.id)",
                                           isRemovable: quran.installedSizes[translation.id] != nil,
                                           disabled: quran.busy || quran.isDownloading)
                    {
                        Task { await quran.remove([translation.id]) }
                    }
                }
            } header: { Text("Quran translations") }
        }
        .navigationTitle("Downloads")
        .toolbar { EditButton() }
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

/// Keeps the trailing swipe action and, while the list is in edit mode,
/// shows a leading red minus button that performs the same removal.
/// Swiping and tapping is already a deliberate two-step gesture, so only the
/// one-tap minus button asks for confirmation. (A destructive swipe button that
/// doesn't remove its row makes the List animate the row out and crash.)
private struct RemoveDownloadControl: ViewModifier {
    @Environment(\.editMode) private var editMode
    let title: LocalizedStringKey
    let id: String
    let isRemovable: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var confirming = false

    func body(content: Content) -> some View {
        HStack {
            if isRemovable, editMode?.wrappedValue.isEditing == true {
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier(id)
                .disabled(disabled)
            }
            content
        }
        .animation(.default, value: editMode?.wrappedValue.isEditing)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isRemovable {
                Button(title, systemImage: "trash", role: .destructive, action: action)
                    .accessibilityIdentifier(id)
                    .disabled(disabled)
            }
        }
        .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
            Button(title, role: .destructive, action: action)
        }
    }
}

extension View {
    func removeDownloadControl(_ title: LocalizedStringKey, id: String, isRemovable: Bool = true,
                               disabled: Bool = false, action: @escaping () -> Void) -> some View
    {
        modifier(RemoveDownloadControl(title: title, id: id, isRemovable: isRemovable,
                                       disabled: disabled, action: action))
    }
}
