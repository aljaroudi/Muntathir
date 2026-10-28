import SwiftUI

struct QuranTranslationStatusView: View {
    private let store = QuranTranslationStore.shared

    var body: some View {
        if let status = store.statuses[store.activeID], status != .installed {
            VStack(alignment: .leading, spacing: 8) {
                switch status {
                case let .downloading(fraction):
                    if let fraction {
                        ProgressView(value: fraction) {
                            Text("Downloading translation")
                        } currentValueLabel: {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }
                        .accessibilityIdentifier("quran-translation-progress")
                    } else {
                        ProgressView("Downloading translation")
                            .accessibilityIdentifier("quran-translation-progress")
                    }
                case .failed:
                    Label("Translation unavailable", systemImage: "exclamationmark.circle")
                    Button("Try again") { store.retryDownload() }
                        .accessibilityIdentifier("quran-translation-retry")
                case .installed:
                    EmptyView()
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
        }
    }
}
