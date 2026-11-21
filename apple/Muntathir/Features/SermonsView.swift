import SQLite3
import SwiftUI

private struct Sermon: Identifiable {
    struct Segment: Identifiable {
        let id, kind, text: String
    }

    struct Edition: Identifiable {
        let id, language, kind: String
        let credit: String?
        let aligned: [String: String]

        var label: String {
            switch kind {
            case "literal": String(localized: "Literal")
            case "simplified": String(localized: "Simplified")
            default: credit ?? ""
            }
        }
    }

    let id, title, speaker: String
    let segments: [Segment]
    let editions: [Edition]

    static func load() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "sermons", withExtension: "db") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let db = try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
        let text = QuranConnection.text
        return try db.query("SELECT id, title, speaker FROM sermon ORDER BY id") { row in
            let id = text(row, 0)
            let segments = try db.query("SELECT id, kind, text FROM segment WHERE sermon = ? ORDER BY position", parameters: [id]) {
                Segment(id: text($0, 0), kind: text($0, 1), text: text($0, 2))
            }
            let editions = try db.query("SELECT id, language, kind, credit FROM edition WHERE sermon = ? ORDER BY position", parameters: [id]) { item in
                let key = text(item, 0)
                let pairs = try db.query("SELECT segment, text FROM translation WHERE sermon = ? AND edition = ?", parameters: [id, key]) {
                    (text($0, 0), text($0, 1))
                }
                return Edition(id: key, language: text(item, 1), kind: text(item, 2),
                               credit: sqlite3_column_type(item, 3) == SQLITE_NULL ? nil : text(item, 3),
                               aligned: Dictionary(uniqueKeysWithValues: pairs))
            }
            return Self(id: id, title: text(row, 1), speaker: text(row, 2), segments: segments, editions: editions)
        }
    }
}

struct SermonsView: View {
    @State private var sermons: [Sermon]?
    @State private var failed = false

    var body: some View {
        Group {
            if let sermons {
                List(sermons) { sermon in
                    NavigationLink {
                        SermonReader(sermon: sermon)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: sermon.title)
                            Text(verbatim: sermon.speaker).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("sermon-\(sermon.id)")
                }
            } else if failed {
                Text("Sermons unavailable")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Sermons")
        .task {
            do { sermons = try Sermon.load() } catch { failed = true }
        }
    }
}

private struct SermonReader: View {
    let sermon: Sermon
    @State private var selection: String?
    @State private var position: String?
    @State private var textSizePresented = false
    @AppStorage("showArabicDiacritics") private var showMarks = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var edition: Sermon.Edition? {
        sermon.editions.first { $0.id == selection }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                ForEach(sermon.segments) { segment in
                    VStack(alignment: .leading, spacing: 14) {
                        if segment.kind == "heading" {
                            passage(arabic(segment.text), language: "ar", centered: true)
                                .readingText(arabic: true, hadith: true, heading: 2)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 12)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("arabic-\(segment.id)")
                        } else {
                            passage(arabic(segment.text), language: "ar")
                                .readingText(arabic: true, hadith: true)
                                .foregroundStyle(segment.kind == "note" ? .secondary : .primary)
                                .accessibilityIdentifier("arabic-\(segment.id)")
                        }
                        if let edition, let text = edition.aligned[segment.id] {
                            passage(text, language: edition.language, marked: true)
                                .readingText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id(segment.id)
                }
            }
            .scrollTargetLayout()
            .textSelection(.enabled)
            .padding(20)
            .readingColumn()
        }
        .scrollPosition(id: $position, anchor: .top)
        .readingBackground()
        .navigationTitle(sermon.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $selection) {
                        Text(verbatim: "العربية").tag(String?.none)
                    } label: {
                        EmptyView()
                    }
                    ForEach(Set(sermon.editions.map(\.language)).sorted(), id: \.self) { language in
                        Menu(nativeName(language)) {
                            Picker(selection: $selection) {
                                ForEach(sermon.editions.filter { $0.language == language }) { item in
                                    Text(item.label).tag(Optional(item.id))
                                }
                            } label: {
                                EmptyView()
                            }
                        }
                        .accessibilityIdentifier("sermon-language-\(language)")
                    }
                } label: {
                    Label(edition.map { nativeName($0.language) + " · " + $0.label } ?? "العربية", systemImage: "character.book.closed")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("sermon-edition")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ReadingSizeMenu(isPresented: $textSizePresented)
                    ArabicDiacriticsToggle()
                } label: {
                    Label("Reading options", systemImage: "textformat")
                }
                .accessibilityIdentifier("reading-options")
                .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(verbatim: sermon.title)
                .readingText(arabic: true, hadith: true, heading: 1)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: sermon.speaker)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 44, height: 3)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.vertical, 8)
    }

    private func arabic(_ text: String) -> String {
        showMarks ? text : ArabicDisplay.plain(text)
    }

    private func nativeName(_ language: String) -> String {
        if language == "zh-CN" {
            return "简体中文"
        }
        return Locale(identifier: language).localizedString(forIdentifier: language) ?? language
    }

    /// Lays out text in its own direction; `marked` adds a leading accent bar that sets translations apart from the Arabic.
    private func passage(_ text: String, language: String, centered: Bool = false, marked: Bool = false) -> some View {
        Text(verbatim: text)
            .multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.leading, marked ? 14 : 0)
            .overlay(alignment: .leading) {
                if marked {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: 2)
                }
            }
            .environment(\.layoutDirection, Locale.Language(identifier: language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}
