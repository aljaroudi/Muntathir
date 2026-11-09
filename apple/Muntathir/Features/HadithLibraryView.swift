import SwiftUI

struct HadithLibraryView: View {
    let assets: HadithAssetStore
    var supplications = false
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
            .id(assets.revision)
        } else {
            ContentUnavailableView {
                Label(LocalizedStringKey(supplications ? "Supplications" : "Hadith"), systemImage: "books.vertical")
            } description: {
                switch assets.state {
                case .checking:
                    Text(LocalizedStringKey(supplications ? "Checking supplications download…" : "Checking Hadith download…"))
                case .downloading:
                    Text(LocalizedStringKey(supplications ? "Downloading supplications…" : "Downloading Hadith…"))
                case .failed:
                    Text(LocalizedStringKey(supplications ? "Unable to download supplications. Check your connection and try again." : "Unable to download Hadith. Check your connection and try again."))
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
                if assets.state == .downloading {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 8) {
                            ProgressView(value: assets.progress)
                                .accessibilityLabel(Text(LocalizedStringKey(supplications ? "Downloading supplications…" : "Downloading Hadith…")))
                            if assets.progress >= 1 {
                                Text(LocalizedStringKey(supplications ? "Checking supplications download…" : "Checking Hadith download…"))
                            } else if let seconds = assets.estimatedRemaining(at: context.date) {
                                Text("About \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))) remaining")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 240)
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
        }
    }
}
