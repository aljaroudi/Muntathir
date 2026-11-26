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

    /// A sermon's text and translations, loaded only when it's opened.
    struct Content {
        let segments: [Segment]
        let editions: [Edition]
    }

    let id, title, speakerID: String

    var route: FigureRoute {
        .sermon(id: id, title: title, speakerID: speakerID)
    }

    /// Lists sermons without their text, so the list stays cheap as sermons are added.
    @concurrent static func load() async throws -> [Self] {
        try open().query("SELECT id, title, speaker_id FROM sermon ORDER BY id") { row in
            Self(id: QuranConnection.text(row, 0), title: QuranConnection.text(row, 1), speakerID: QuranConnection.text(row, 2))
        }
    }

    @concurrent func content() async throws -> Content {
        let db = try Self.open()
        let text = QuranConnection.text
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
        return Content(segments: segments, editions: editions)
    }

    private static func open() throws -> QuranConnection {
        guard let url = Bundle.main.url(forResource: "sermons", withExtension: "db") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
    }
}

struct SermonsView: View {
    @Environment(\.locale) private var locale
    @State private var sermons: [Sermon]?
    @State private var figures: FigureLibrary?
    @State private var failed = false

    var body: some View {
        AdaptiveSplit(restorationKey: "sermons", defaultSelection: sermons?.first.map(\.route)) { selection in
            list(selection: selection)
        }
    }

    private func list(selection: Binding<FigureRoute?>) -> some View {
        Group {
            if let sermons {
                AdaptiveList(selection: selection) {
                    ForEach(sermons) { sermon in
                        // Value-based so the reader lives in the stack's path; a view-based push gets
                        // re-pushed when the speaker link appends a figure profile to the path.
                        AdaptiveLink(route: sermon.route) {
                            VStack(alignment: .leading) {
                                Text(verbatim: sermon.title)
                                if let speaker = figures?.byID[sermon.speakerID] {
                                    Text(verbatim: speaker.title(locale)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("sermon-\(sermon.id)")
                    }
                }
            } else if failed {
                Text("Sermons unavailable")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Sermons")
        .task {
            do { sermons = try await Sermon.load() } catch { failed = true }
            figures = try? await FigureStore.shared.load().get()
        }
    }
}

struct SermonDestination: View {
    let id, title, speakerID: String
    @State private var speaker: Figure?

    var body: some View {
        SermonReader(sermon: Sermon(id: id, title: title, speakerID: speakerID), speaker: speaker)
            .task {
                speaker = try? await FigureStore.shared.load().get().byID[speakerID]
            }
    }
}

private struct SermonReader: View {
    let sermon: Sermon
    let speaker: Figure?
    @Environment(\.locale) private var locale
    @State private var content: Sermon.Content?
    @State private var failed = false
    @State private var selection: String?
    @State private var position: String?
    @State private var textSizePresented = false
    @AppStorage("showArabicDiacritics") private var showMarks = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var edition: Sermon.Edition? {
        content?.editions.first { $0.id == selection }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                if content == nil {
                    Group {
                        if failed {
                            Text("Sermons unavailable")
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                ForEach(content?.segments ?? []) { segment in
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
        .task {
            do { content = try await sermon.content() } catch { failed = true }
        }
        .navigationTitle(sermon.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Picker(selection: $selection) {
                        Text(verbatim: "العربية").tag(String?.none)
                    } label: {
                        EmptyView()
                    }
                    ForEach(Set((content?.editions ?? []).map(\.language)).sorted(), id: \.self) { language in
                        Menu(nativeName(language)) {
                            Picker(selection: $selection) {
                                ForEach((content?.editions ?? []).filter { $0.language == language }) { item in
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
            ToolbarItem(placement: .trailingBar) {
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
            DictionarySelectableText(text: sermon.title, heading: 1, centered: true)
                .accessibilityAddTraits(.isHeader)
            if let speaker {
                NavigationLink(value: FigureRoute.profile(speaker.id)) {
                    Text(verbatim: speaker.title(locale))
                        .font(.subheadline)
                }
                .accessibilityIdentifier("sermon-speaker")
            }
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
        DictionarySelectableText(text: text, arabic: language == "ar", heading: centered ? 2 : nil, centered: centered)
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
