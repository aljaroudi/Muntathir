import SwiftUI

struct ReadingTimeHint: View {
    let words: Int
    @Environment(\.locale) private var locale

    var body: some View {
        if let duration = ReadingTime.duration(words: words) {
            let value = duration.formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Estimated reading time: \(value)"))
                .accessibilityIdentifier("reading-time")
        }
    }
}
