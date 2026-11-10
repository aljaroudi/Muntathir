import Foundation

struct SavedEntrySection: Identifiable {
    let id: String
    let date: Date?
    let entries: [SavedEntry]
}
