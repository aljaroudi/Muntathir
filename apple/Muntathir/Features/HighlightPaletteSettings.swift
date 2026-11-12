import SwiftUI

struct HighlightPaletteSettings: View {
    @AppStorage("highlightColorCount") private var count = HighlightPalette.defaultCount
    @AppStorage("highlightColorOrder") private var order = HighlightPalette.defaultOrder

    var body: some View {
        List {
            Section {
                Stepper(value: $count, in: 1 ... HighlightColor.allCases.count) {
                    LabeledContent("Colors shown", value: count, format: .number)
                }
                .accessibilityIdentifier("highlight-color-count")
                .accessibilityValue(Text(count, format: .number))
            }
            Section {
                ForEach(HighlightPalette.colors(order: order), id: \.self) { color in
                    HStack {
                        HighlightSwatch(color: color, size: 32)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(color.title)
                    .accessibilityIdentifier("palette-color-\(color.rawValue)")
                }
                .onMove { source, destination in
                    var colors = HighlightPalette.colors(order: order)
                    colors.move(fromOffsets: source, toOffset: destination)
                    order = colors.map(\.rawValue).joined(separator: ",")
                }
            } footer: {
                Text("Drag colors to reorder them. The first colors appear in the picker.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Highlight colors")
    }
}
