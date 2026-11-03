import SwiftUI

struct HadithLibraryView: View {
    let assets: HadithAssetStore
    @State private var confirmingRemoval = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Group {
            if assets.state == .ready {
                #if DEBUG
                    HadithView(reader: assets.reader) { confirmingRemoval = true }
                        .id(assets.revision)
                #else
                    HadithView(reader: assets.reader)
                        .id(assets.revision)
                #endif
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
                        Text("This Hadith download needs an update. Download the compatible version, or update the app if the problem continues.")
                    default:
                        Text("Download the Hadith library to read and search offline. Estimated download: 88 MiB. Storage: 223 MiB.")
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
                                } else {
                                    Text("Estimating time remaining…")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 240)
                    } else if assets.state == .checking {
                        ProgressView()
                    } else {
                        Button(LocalizedStringKey(assets.state == .missing ? "Download Hadith" : "Try again")) {
                            operation = Task { await assets.download() }
                        }
                        .disabled(assets.busy)
                        .accessibilityIdentifier("hadith-download")
                    }
                }
                .navigationTitle("Hadith")
            }
        }
        .confirmationDialog("Remove Hadith download?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove download", role: .destructive) {
                operation = Task { await assets.remove() }
            }
        } message: {
            Text("You can download it again later. Quran will remain available.")
        }
    }
}
