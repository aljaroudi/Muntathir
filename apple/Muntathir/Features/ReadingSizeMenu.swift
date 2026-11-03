import SwiftUI

struct ReadingSizeMenu: View {
    @AppStorage("readingSizePercent") private var percent = 100

    var body: some View {
        Menu {
            Picker("Text size", selection: $percent) {
                ForEach(Array(stride(from: 80, through: 160, by: 10)), id: \.self) { value in
                    Text(Double(value) / 100, format: .percent.precision(.fractionLength(0)))
                        .tag(value)
                        .accessibilityIdentifier("reading-size-\(value)")
                }
            }
            Button("Reset") { percent = 100 }
                .accessibilityIdentifier("reading-size-reset")
        } label: {
            Label {
                Text(verbatim: String(localized: "Text size") + " · " + (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0))))
            } icon: {
                Image(systemName: "textformat.size")
            }
        }
        .accessibilityIdentifier("reading-size")
        .accessibilityValue((Double(percent) / 100).formatted(.percent.precision(.fractionLength(0))))
    }
}
