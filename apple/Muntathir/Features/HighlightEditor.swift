import SwiftUI

extension HighlightColor {
    var color: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        }
    }

    var title: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        }
    }
}

struct HighlightEditor: View {
    @Environment(\.quranUserStore) private var store
    @Environment(\.dismiss) private var dismiss
    let original: ReadingHighlight
    let existing: Bool
    // A draft is seeded once when the editor opens; incoming sync never replaces unsaved typing.
    @State private var draft: ReadingHighlight
    @State private var discard = false
    @State private var deleting = false
    @State private var failed = false
    @State private var editingNote = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var noteFocused: Bool

    init(highlight: ReadingHighlight, existing: Bool = false) {
        original = highlight
        self.existing = existing
        _draft = State(initialValue: highlight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        ForEach(HighlightColor.allCases, id: \.self) { color in
                            Button {
                                draft.color = color
                                if !editingNote {
                                    save()
                                }
                            } label: {
                                Circle().fill(color.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if draft.color == color {
                                            Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(.black)
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
                    if editingNote {
                        TextEditor(text: $draft.note)
                            .frame(minHeight: 140)
                            .focused($noteFocused)
                            .accessibilityLabel("Highlight note")
                            .accessibilityIdentifier("highlight-note-editor")
                    } else if !draft.note.isEmpty {
                        Text(draft.note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("highlight-note-preview")
                    }
                    if !editingNote {
                        HStack {
                            Button(draft.note.isEmpty ? "Add note" : "Edit note", systemImage: "square.and.pencil") {
                                editingNote = true
                                noteFocused = true
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("highlight-add-note")
                            Spacer()
                            if existing {
                                Button("Delete highlight", systemImage: "trash", role: .destructive) { deleting = true }
                                    .labelStyle(.iconOnly)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .navigationTitle(editingNote ? Text("Highlight note") : Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editingNote || !existing ? "Cancel" : "Done") {
                        noteFocused = false
                        if draft != original {
                            discard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                if editingNote {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.accessibilityIdentifier("save-highlight")
                    }
                }
            }
            .interactiveDismissDisabled(draft != original)
            .confirmationDialog("Unsaved highlight", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { noteFocused = editingNote }
            }
            .confirmationDialog("Delete this highlight?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete highlight", role: .destructive) { save(deleting: true) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Unable to save", isPresented: $failed) { Button("OK", role: .cancel) {} }
            message: { Text("Your changes are still here. Please try saving again.") }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }

    private var detents: Set<PresentationDetent> {
        if editingNote || typeSize.isAccessibilitySize {
            return [.medium, .large]
        }
        return draft.note.isEmpty ? [.height(220)] : [.height(320), .large]
    }

    private func save(deleting: Bool = false) {
        do {
            guard let store else { throw QuranUserStoreError.unavailable }
            if deleting {
                try store.delete(original)
            } else {
                try store.save(draft)
            }
            dismiss()
        } catch { failed = true }
    }
}

struct HighlightActions: View {
    let source: String
    let isHadith: Bool
    let excerpt: String
    let reference: String
    @Environment(\.quranUserStore) private var store
    @Binding var editing: ReadingHighlight?

    var body: some View {
        Button("Highlight", systemImage: "highlighter") {
            editing = ReadingHighlight(source: source, isHadith: isHadith, excerpt: excerpt, reference: reference)
        }.disabled(source.isEmpty)
        ForEach(store?.highlights(for: source, isHadith: isHadith) ?? []) { highlight in
            Button {
                editing = highlight
            } label: {
                Label(String(localized: "Edit highlight") + " · " + highlight.color.title + " · " + String(highlight.excerpt.prefix(35)), systemImage: "pencil")
            }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(highlight.color.color)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(reference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(reference + ", " + highlight.color.title)
                Text(highlight.excerpt)
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
