import SwiftUI

struct ReadingTimeHint: View {
    let words: Int
    var showsIcon = false
    @Environment(\.locale) private var locale

    var body: some View {
        if let duration = ReadingTime.duration(words: words) {
            let value = duration.formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
            Group {
                if showsIcon {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").accessibilityHidden(true)
                        Text(value)
                    }
                } else {
                    Text(value)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Estimated reading time: \(value)"))
            .accessibilityIdentifier("reading-time")
        }
    }
}
