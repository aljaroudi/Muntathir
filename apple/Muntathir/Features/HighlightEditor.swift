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
        case .cyan: Color(red: 0.67, green: 0.66, blue: 0.88)
        case .indigo: .indigo
        case .brown: .brown
        }
    }

    var fillStyle: AnyShapeStyle {
        if self == .cyan {
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.66, green: 0.82, blue: 0.96),
                         Color(red: 0.85, green: 0.80, blue: 0.95),
                         Color(red: 0.72, green: 0.69, blue: 0.90)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        } else {
            AnyShapeStyle(color)
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
        case .cyan: String(localized: "Pearl")
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
    @State private var selectedColor: HighlightColor?
    @State private var lastSaved: ReadingHighlight?
    @State private var pendingRetry: SaveAction?
    @State private var failed = false
    @State private var paletteHeight: CGFloat = 136

    private enum SaveAction {
        case note, color, delete
    }

    @AppStorage("highlightColorCount") private var colorCount = HighlightPalette.defaultCount
    @AppStorage("highlightColorOrder") private var colorOrder = HighlightPalette.defaultOrder

    init(highlight: ReadingHighlight, existing: Bool = false, additionalHighlights: [ReadingHighlight] = []) {
        self.additionalHighlights = additionalHighlights
        original = highlight
        self.existing = existing
        _draft = State(initialValue: highlight)
        _selectedColor = State(initialValue: existing ? highlight.color : nil)
        _lastSaved = State(initialValue: existing ? highlight : nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                palette
                if existing {
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
                            .accessibilityLabel("Highlight note")
                            .accessibilityIdentifier("highlight-note-editor")
                            .onChange(of: draft.note) { save(.note) }
                    }
                    HStack {
                        Button("Delete highlight", systemImage: "trash", role: .destructive) { deleting = true }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, existing ? 16 : 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .interactiveDismissDisabled(pendingRetry != nil && pendingRetry != .delete)
        .confirmationDialog("Delete this highlight?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete highlight", role: .destructive) { save(.delete) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Unable to save", isPresented: $failed) {
            Button("Retry") {
                if let pendingRetry {
                    save(pendingRetry)
                }
            }
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        .presentationDetents(existing ? [.medium, .large] : [.height(paletteHeight + 24)])
        .presentationDragIndicator(.visible)
    }

    private var palette: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(HighlightPalette.colors(order: colorOrder, count: colorCount), id: \.self) { color in
                Button {
                    selectedColor = color
                    draft.color = color
                    save(.color)
                } label: {
                    HighlightSwatch(color: color, size: 36, isSelected: selectedColor == color)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                .accessibilityIdentifier("highlight-color-\(color.rawValue)")
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paletteHeight = $0 }
    }

    private func save(_ action: SaveAction) {
        do {
            if action == .delete {
                guard let store else { throw QuranUserStoreError.unavailable }
                try store.delete(original)
            } else if draft != lastSaved {
                guard let store else { throw QuranUserStoreError.unavailable }
                let additional = additionalHighlights.map { highlight in
                    var value = highlight
                    value.color = draft.color
                    value.note = draft.note
                    return value
                }
                try store.save([draft] + additional)
                lastSaved = draft
            }
            pendingRetry = nil
            if action != .note {
                dismiss()
            }
        } catch {
            pendingRetry = action
            failed = true
        }
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
    var searchQuery = ""

    var body: some View {
        let searching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let blocks = [SearchMatch.text(highlight.excerpt, query: searchQuery), SearchMatch.text(highlight.note, query: searchQuery)]
        let visible = SearchMatch.visibleBlocks(blocks, preferred: 0)
        HStack(alignment: .top, spacing: 12) {
            HighlightMarker(color: highlight.color)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if showReference {
                    Text(reference)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(reference + ", " + highlight.color.title)
                }
                if searching {
                    ForEach(visible, id: \.self) { index in
                        SearchMatchText(SearchMatch.preview(blocks[index], compact: true))
                            .font(index == 0 ? .body : .subheadline)
                            .lineLimit(2)
                    }
                } else {
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
