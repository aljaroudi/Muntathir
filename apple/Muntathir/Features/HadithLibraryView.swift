import SwiftUI

struct HadithLibraryView: View {
    let assets: HadithAssetStore
    @State private var operation: Task<Void, Never>?

    var body: some View {
        if assets.state == .ready {
            HadithView(reader: assets.reader)
                .id(assets.revision)
        } else {
            ContentUnavailableView {
                Label("Hadith", systemImage: "books.vertical")
            } description: {
                switch assets.state {
                case .checking:
                    Text("Checking Hadith download…")
                case .downloading:
                    Text("Downloading Hadith…")
                case .failed:
                    Text("Unable to download Hadith. Check your connection and try again.")
                case .incompatible:
                    Text("This download needs an update.")
                default:
                    Text("Read and search Hadith offline.")
                }
            } actions: {
                if assets.state == .downloading {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 8) {
                            ProgressView(value: assets.progress)
                                .accessibilityLabel("Downloading Hadith…")
                            if assets.progress >= 1 {
                                Text("Checking Hadith download…")
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
                    AssetDownloadButton(pack: "hadith", retry: assets.state != .missing) {
                        operation = Task { await assets.download() }
                    }
                    .disabled(assets.busy)
                    .accessibilityIdentifier("hadith-download")
                }
            }
            .navigationTitle("Hadith")
        }
    }
}
