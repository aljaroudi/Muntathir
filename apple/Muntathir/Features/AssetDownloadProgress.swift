import SwiftUI

struct AssetDownloadProgress: View {
    let progress: Progress?
    var installing = false
    var preparing = false
    var remaining: ((Date) -> TimeInterval?)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let installing = installing || (progress?.fractionCompleted ?? 0) >= 1
            let fraction = installing ? nil : measurableFraction
            let label: LocalizedStringKey = installing ? "Installing…" : (preparing ? "Preparing download…" : "Downloading…")
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction) {
                    Text(label)
                } currentValueLabel: {
                    if let fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
                .progressViewStyle(.linear)
                if fraction != nil, let seconds = remaining?(context.date) {
                    Text("About \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))) remaining")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("asset-download-progress")
    }

    private var measurableFraction: Double? {
        guard let progress, progress.totalUnitCount > 0 else { return nil }
        let fraction = progress.fractionCompleted
        return fraction.isFinite ? min(1, max(0, fraction)) : nil
    }
}
