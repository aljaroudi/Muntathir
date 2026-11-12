import SwiftUI

extension HighlightColor {
    var color: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        case .orange: .orange
        case .red: .red
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .indigo: .indigo
        case .brown: .brown
        }
    }

    /// Opaque pastel/deep fills keep label text readable independently of the reading surface.
    var textBackground: UIColor {
        Self.textBackgrounds[self]!
    }

    /// Reuse dynamic color objects so unchanged attributed text compares equal across view updates.
    private static let textBackgrounds = Dictionary(uniqueKeysWithValues: allCases.map { color in
        let swatch = UIColor(color.color)
        return (color, UIColor { traits in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            swatch.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let dark = traits.userInterfaceStyle == .dark
            let fraction: CGFloat = traits.accessibilityContrast == .high ? 0.22 : 0.28
            let base: CGFloat = dark ? 0 : 1 - fraction
            return UIColor(red: base + red * fraction, green: base + green * fraction,
                           blue: base + blue * fraction, alpha: 1)
        })
    })

    var title: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .mint: String(localized: "Mint")
        case .teal: String(localized: "Teal")
        case .cyan: String(localized: "Cyan")
        case .indigo: String(localized: "Indigo")
        case .brown: String(localized: "Brown")
        }
    }
}

struct HighlightEditor: View {
    @Environment(\.quranUserStore) private var store
    @Environment(\.dismiss) private var dismiss
    let original: ReadingHighlight
    let existing: Bool
    let additionalHighlights: [ReadingHighlight]
    // A draft is seeded once when the editor opens; incoming sync never replaces unsaved typing.
    @State private var draft: ReadingHighlight
    @State private var deleting = false
    @State private var failed = false
    @AppStorage("highlightColorCount") private var colorCount = HighlightPalette.defaultCount
    @AppStorage("highlightColorOrder") private var colorOrder = HighlightPalette.defaultOrder
    @FocusState private var noteFocused: Bool

    init(highlight: ReadingHighlight, existing: Bool = false, additionalHighlights: [ReadingHighlight] = []) {
        self.additionalHighlights = additionalHighlights
        original = highlight
        self.existing = existing
        _draft = State(initialValue: highlight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(HighlightPalette.colors(order: colorOrder, count: colorCount), id: \.self) { color in
                            Button {
                                draft.color = color
                                if !noteFocused, draft.note == original.note {
                                    save()
                                }
                            } label: {
                                Circle().fill(color.color)
                                    .overlay { Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 1) }
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if draft.color == color {
                                            Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(color == .indigo || color == .brown || color == .blue || color == .purple ? .white : .black)
                                        }
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(draft.color == color ? .isSelected : [])
                            .accessibilityIdentifier("highlight-color-\(color.rawValue)")
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        if draft.note.isEmpty {
                            Text("Add note")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $draft.note)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .focused($noteFocused)
                            .accessibilityLabel("Highlight note")
                            .accessibilityIdentifier("highlight-note-editor")
                    }
                    if existing {
                        HStack {
                            Button("Delete highlight", systemImage: "trash", role: .destructive) { deleting = true }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .accessibilityIdentifier("save-highlight")
                }
            }
            .interactiveDismissDisabled(existing ? draft != original : !draft.note.isEmpty)
            .confirmationDialog("Delete this highlight?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete highlight", role: .destructive) { save(deleting: true) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Unable to save", isPresented: $failed) {
                Button("OK", role: .cancel) {}
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            message: { Text("Your changes are still here. Please try saving again.") }
        }
        .onAppear {
            if !existing, let first = HighlightPalette.colors(order: colorOrder, count: colorCount).first {
                draft.color = first
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save(deleting: Bool = false) {
        if existing, !deleting, draft == original {
            dismiss()
            return
        }
        do {
            guard let store else { throw QuranUserStoreError.unavailable }
            if deleting {
                try store.delete(original)
            } else {
                let additional = additionalHighlights.map { highlight in
                    var value = highlight
                    value.color = draft.color
                    value.note = draft.note
                    return value
                }
                try store.save([draft] + additional)
            }
            dismiss()
        } catch { failed = true }
    }
}

struct HighlightSummary: View {
    @Environment(\.locale) private var locale

    private var reference: String {
        highlight.isHadith || locale.language.languageCode?.identifier != "ar"
            ? highlight.reference : QuranReference.display(highlight.source, locale: locale)
    }

    let highlight: ReadingHighlight
    var available = true
    var showReference = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(highlight.color.color)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if showReference {
                    Text(reference)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(reference + ", " + highlight.color.title)
                }
                Text(highlight.excerpt)
                    .accessibilityLabel(showReference ? highlight.excerpt : reference + ", " + highlight.color.title + ", " + highlight.excerpt)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                if !highlight.note.isEmpty {
                    Label(highlight.note, systemImage: "note.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !available {
                    Label("Highlighted passage unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}
