import SwiftUI

struct ReleaseNote: Decodable {
    let version: String
    let platforms: [String]
    let notes: [String: [String]]
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

    /// iOS and macOS ship the same versions together, so the `ios` date covers both.
    /// It's a calendar day (`yyyy-MM-dd`), parsed and shown in GMT so it never shifts by a day.
    var releaseDate: Date? {
        releaseDates?["ios"].flatMap { try? Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().parse($0) }
    }

    static func hasUnseenNotes(since seen: String, installed: String, history: [ReleaseNote]) -> Bool {
        history.contains { entry in
            guard entry.version.compare(installed, options: .numeric) != .orderedDescending else { return false }
            return seen.isEmpty ? entry.version == installed : entry.version.compare(seen, options: .numeric) == .orderedDescending
        }
    }

    func items(for locale: Locale) -> [String] {
        let match = Bundle.preferredLocalizations(from: Array(notes.keys), forPreferences: [locale.identifier, "en-US"]).first
        return match.flatMap { notes[$0] } ?? notes["en-US"] ?? []
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

    func body(content: Content) -> some View {
        content.onAppear {
            guard seen.compare(ReleaseNote.installed, options: .numeric) == .orderedAscending else { return }
            showing = ReleaseNote.hasUnseenNotes(since: seen, installed: ReleaseNote.installed, history: ReleaseNote.history)
            if !showing {
                seen = ReleaseNote.installed
            }
        }
        .sheet(isPresented: $showing, onDismiss: { seen = ReleaseNote.installed }) {
            NavigationStack {
                ReleaseNotesList(entries: ReleaseNote.history)
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
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.items(for: locale), id: \.self) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "•").accessibilityHidden(true)
                            Text(verbatim: item)
                        }
                    }
                }
            } header: {
                Text(verbatim: entry.version)
            } footer: {
                if let day = entry.releaseDate {
                    Text(day, format: Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .gmt))
                }
            }
        }
        .navigationTitle("What’s New")
    }
}
