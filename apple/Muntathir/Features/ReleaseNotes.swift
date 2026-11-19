import SwiftUI

struct ReleaseNote: Decodable {
    let version: String
    let platforms: [String]
    let notes: [String: String]
    var releaseDates: [String: String]? = nil

    static let seenKey = "lastSeenReleaseVersion"
    static let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let history: [ReleaseNote] = {
        guard let url = Bundle.main.url(forResource: "changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return entries.filter { $0.platforms.contains("ios") && $0.version.compare(installed, options: .numeric) != .orderedDescending }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }()

    static func pending(since seen: String, installed: String, history: [ReleaseNote]) -> [ReleaseNote] {
        history.filter { entry in
            guard entry.version.compare(installed, options: .numeric) != .orderedDescending else { return false }
            return seen.isEmpty ? entry.version == installed : entry.version.compare(seen, options: .numeric) == .orderedDescending
        }
    }

    func text(for locale: Locale) -> String {
        let match = Bundle.preferredLocalizations(from: Array(notes.keys), forPreferences: [locale.identifier, "en-US"]).first
        return match.flatMap { notes[$0] } ?? notes["en-US"] ?? ""
    }
}

struct FreshInstallReleaseMarker: ViewModifier {
    @AppStorage(ReleaseNote.seenKey) private var seen = ""
    func body(content: Content) -> some View {
        content.onAppear { seen = ReleaseNote.installed }
    }
}

struct ReleaseNotesPrompt: ViewModifier {
    @AppStorage(ReleaseNote.seenKey) private var seen = ""
    @State private var showing = false
    private var pending: [ReleaseNote] {
        ReleaseNote.pending(since: seen, installed: ReleaseNote.installed, history: ReleaseNote.history)
    }

    func body(content: Content) -> some View {
        content.onAppear {
            guard seen.compare(ReleaseNote.installed, options: .numeric) == .orderedAscending else { return }
            if pending.isEmpty {
                seen = ReleaseNote.installed
            } else {
                showing = true
            }
        }
        .sheet(isPresented: $showing, onDismiss: { seen = ReleaseNote.installed }) {
            NavigationStack {
                ReleaseNotesList(entries: pending)
                    .toolbar { Button("Done") { showing = false }.accessibilityIdentifier("dismiss-release-notes") }
            }
        }
    }
}

struct ReleaseNotesList: View {
    let entries: [ReleaseNote]
    @Environment(\.locale) private var locale

    var body: some View {
        List(entries, id: \.version) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: entry.version).font(.headline).accessibilityAddTraits(.isHeader)
                if let day = entry.releaseDates?["ios"] {
                    Text(verbatim: day)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(verbatim: entry.text(for: locale))
            }
        }
        .navigationTitle("What’s New")
    }
}
