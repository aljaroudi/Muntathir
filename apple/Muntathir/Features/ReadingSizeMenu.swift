import SwiftUI

struct ReadingSizeMenu: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button("Text size", systemImage: "textformat.size") { isPresented = true }
            .accessibilityIdentifier("reading-size")
    }
}

struct ReadingSizeControls: View {
    @AppStorage("showArabicDiacritics") private var showMarks = true
    @AppStorage("readingSizePercent") private var percent = 100

    var body: some View {
        VStack(spacing: 16) {
            Text("Text size").font(.headline)
            HStack(spacing: 0) {
                Button { percent = max(80, percent - 10) } label: {
                    Text(verbatim: "A").font(.system(size: 18))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(percent <= 80)
                .accessibilityLabel("Decrease text size")
                .accessibilityIdentifier("reading-size-decrease")
                .accessibilityValue((Double(percent) / 100).formatted(.percent))
                Text((Double(percent) / 100).formatted(.percent))
                    .monospacedDigit()
                Button { percent = min(160, percent + 10) } label: {
                    Text(verbatim: "A").font(.system(size: 30))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(percent >= 160)
                .accessibilityLabel("Increase text size")
                .accessibilityIdentifier("reading-size-increase")
                .accessibilityValue((Double(percent) / 100).formatted(.percent))
            }
            .buttonStyle(.borderless)
            .background(.quaternary, in: .rect(cornerRadius: 12))
            .accessibilityValue((Double(percent) / 100).formatted(.percent))
            Button("Reset") { percent = 100 }
                .disabled(percent == 100)
                .accessibilityIdentifier("reading-size-reset")
            Toggle(isOn: $showMarks) {
                Text("Show Arabic diacritics")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .accessibilityIdentifier("reading-diacritics")
            Text(verbatim: showMarks ? "بِسْمِ اللَّهِ" : ArabicDisplay.plain("بِسْمِ اللَّهِ"))
                .readingText(arabic: true)
                .accessibilityIdentifier("reading-preview")
        }
        .padding(.vertical, 8)
    }
}

extension View {
    func readingSizePresentation(isPresented: Binding<Bool>, compact: Bool) -> some View {
        modifier(ReadingSizePresentation(isPresented: isPresented, compact: compact))
    }
}

private struct ReadingSizePresentation: ViewModifier {
    @Binding var isPresented: Bool
    let compact: Bool

    func body(content: Content) -> some View {
        if !compact {
            content.popover(isPresented: $isPresented) { panel }
        } else {
            content.sheet(isPresented: $isPresented) {
                ScrollView { panel }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var panel: some View {
        ReadingSizeControls()
            .padding(24)
            .frame(minWidth: 280)
            .fixedSize(horizontal: false, vertical: true)
    }
}
