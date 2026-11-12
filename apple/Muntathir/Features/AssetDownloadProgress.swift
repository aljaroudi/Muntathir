import SwiftUI

struct AssetDownloadProgress: View {
    let progress: Progress?
    var installing = false
    var preparing = false
    var remaining: ((Date) -> TimeInterval?)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if installing || (progress?.fractionCompleted ?? 0) >= 1 {
                    ProgressView("Installing…")
                } else if let progress, progress.totalUnitCount > 0, progress.fractionCompleted.isFinite {
                    HStack {
                        Text("Downloading…")
                        Spacer()
                        Text(min(1, max(0, progress.fractionCompleted)), format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    ProgressView(value: min(1, max(0, progress.fractionCompleted)))
                        .accessibilityLabel("Downloading…")
                    if let seconds = remaining?(context.date) {
                        Text("About \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))) remaining")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView {
                        Text(preparing ? LocalizedStringKey("Preparing download…") : LocalizedStringKey("Downloading…"))
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("asset-download-progress")
    }
}
