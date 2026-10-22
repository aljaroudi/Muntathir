import SwiftUI

struct VerseNoteEditor: View {
    let verseID: String
    @Environment(\.quranUserStore) private var store
    @Environment(\.dismiss) private var dismiss
    // A draft is seeded once when the editor opens; incoming sync never replaces unsaved typing.
    @State private var draft: String
    @State private var original: String
    @State private var discard = false
    @State private var deleting = false
    @State private var failed = false

    init(verseID: String, initialNote: String) {
        self.verseID = verseID
        _draft = State(initialValue: initialNote)
        _original = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 240)
                        .accessibilityLabel("Verse note")
                        .accessibilityIdentifier("verse-note-editor")
                } header: { Text(verseID) }
                if !original.isEmpty {
                    Button("Delete note", role: .destructive) { deleting = true }
                }
            }
            .navigationTitle("Verse note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft != original {
                            discard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(draft) }
                        .accessibilityIdentifier("save-verse-note")
                        .disabled(draft == original)
                }
            }
            .interactiveDismissDisabled(draft != original)
            .confirmationDialog("Unsaved note", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Delete this note?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { save("") }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Unable to save", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your note is still here. Please try saving again.") }
        }
    }

    private func save(_ text: String) {
        do {
            guard let store else { throw QuranUserStoreError.unavailable }
            try store.setNote(text, for: verseID)
            original = text
            dismiss()
        } catch { failed = true }
    }
}
