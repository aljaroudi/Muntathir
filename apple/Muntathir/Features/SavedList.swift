import SwiftUI

struct SavedList<Destination: View>: View {
    var bookmarksOnly = false
    let highlights: [ReadingHighlight]
    let bookmarks: [ReadingBookmark]
    let canOpen: (SavedEntry) -> Bool
    let available: (ReadingHighlight) -> Bool
    @ViewBuilder let destination: (SavedEntry) -> Destination
    @Environment(\.quranUserStore) private var store
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @AppStorage("savedGroupByDate") private var byDate = false
    @State private var showingBookmarks = false
    @State private var query = ""
    @State private var submitted = ""
    /// Sections for the submitted search, rebuilt only when their inputs change, never per keystroke.
    @State private var sections: [SavedEntrySection] = []
    @State private var editing: ReadingHighlight?
    @State private var failed = false

    private var entries: [SavedEntry] {
        (bookmarksOnly || showingBookmarks) ? bookmarks.map(SavedEntry.init) : highlights.map(SavedEntry.init)
    }

    private var localCalendar: Calendar {
        var result = calendar
        result.timeZone = timeZone
        return result
    }

    private struct SectionInputs: Equatable {
        let highlights: [ReadingHighlight]
        let bookmarks: [ReadingBookmark]
        let showsBookmarks: Bool
        let byDate: Bool
        let query: String
        let calendar: Calendar
        let locale: Locale
    }

    @AppStorage("showArabicDiacritics") private var showMarks = true
    var body: some View {
        let savedEntries = entries
        List {
            if !bookmarksOnly {
                Picker("Saved", selection: $showingBookmarks) {
                    Text("Highlights").tag(false)
                    Text("Bookmarks").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("saved-kind")
            }
            if savedEntries.isEmpty {
                if bookmarksOnly || showingBookmarks {
                    ContentUnavailableView("No bookmarks yet", systemImage: "bookmark", description: Text("Use Bookmark to save a passage."))
                } else {
                    ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("Select text to highlight it."))
                }
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: submitted)
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { actions(entry) }
                                .contextMenu { actions(entry) }
                        }
                    } header: {
                        if !submitted.isEmpty {
                            Text(section.id == "related" ? "Related matches" : "Matches")
                        } else if let date = section.date {
                            if localCalendar.isDateInToday(date) {
                                Text("Today")
                            } else if localCalendar.isDateInYesterday(date) {
                                Text("Yesterday")
                            } else {
                                Text(date, format: Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: localCalendar, timeZone: timeZone))
                            }
                        } else {
                            Text(section.entries[0].title(locale: locale))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Saved")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: (bookmarksOnly || showingBookmarks) ? "Search bookmarks" : "Search highlights")
        .searchHistory($query, area: .saved)
        .submitsSearch($query, submitted: $submitted)
        .onChange(
            of: SectionInputs(
                highlights: highlights,
                bookmarks: bookmarks,
                showsBookmarks: bookmarksOnly || showingBookmarks,
                byDate: byDate,
                query: submitted,
                calendar: localCalendar,
                locale: locale
            ),
            initial: true
        ) { _, inputs in
            sections = SavedEntry.sections(entries, byDate: inputs.byDate, query: inputs.query, calendar: inputs.calendar, locale: inputs.locale)
        }
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            Menu("Grouping", systemImage: "ellipsis.circle") {
                Picker("Grouping", selection: $byDate) {
                    Text("Group by Source").tag(false)
                    Text("Group by Date").tag(true)
                }
            }
            .accessibilityIdentifier("saved-grouping")
        }
        .sheet(item: $editing) { HighlightEditor(highlight: $0, existing: true) }
        .alert("Unable to save bookmark", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try again.") }
    }

    @ViewBuilder private func row(_ entry: SavedEntry) -> some View {
        if canOpen(entry) {
            NavigationLink { destination(entry).recordSearchOnOpen(submitted, area: .saved) } label: { summary(entry) }
                .accessibilityIdentifier((entry.ruling != nil ? "saved-ruling-" : entry.isHadith ? "saved-hadith-" : "saved-verse-") + entry.source)
        } else if let highlight = entry.highlight {
            Button { SearchHistory.shared.record(submitted, in: .saved); editing = highlight } label: { summary(entry) }
                .tint(.primary)
        } else {
            summary(entry)
        }
    }

    @ViewBuilder private func summary(_ entry: SavedEntry) -> some View {
        if let highlight = entry.highlight {
            HighlightSummary(highlight: highlight, available: available(highlight), showReference: byDate, searchQuery: submitted)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if byDate {
                    Text(entry.title(locale: locale)).font(.subheadline).foregroundStyle(.secondary)
                }
                if submitted.isEmpty {
                    Text(showMarks ? entry.excerpt : ArabicDisplay.plain(entry.excerpt)).font(.body).lineLimit(4)
                } else {
                    SearchMatchText(SearchMatch.preview(SearchMatch.text(entry.excerpt, query: submitted), compact: true))
                        .font(.body).lineLimit(2)
                }
                if !canOpen(entry) {
                    Label("Saved passage unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func actions(_ entry: SavedEntry) -> some View {
        if let highlight = entry.highlight {
            Button("Edit highlight", systemImage: "pencil") { editing = highlight }.tint(.accentColor)
        } else if let bookmark = entry.bookmark {
            Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                do {
                    guard let store else { throw QuranUserStoreError.unavailable }
                    try store.delete(bookmark)
                } catch { failed = true }
            }
        }
    }
}
