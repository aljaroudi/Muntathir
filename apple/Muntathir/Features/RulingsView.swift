import SwiftUI

struct RulingsView: View {
    @Environment(\.rulingsAssets) private var assets

    var body: some View {
        if let assets {
            if assets.state == .ready {
                RulingsBrowser(reader: assets.reader)
                    .id(assets.revision)
            } else {
                List { RulingsIntroSection(); RulingsDownloadSection(assets: assets) }
                    .navigationTitle("Rulings")
            }
        }
    }
}

struct RulingsDownloadSection: View {
    @Bindable var assets: RulingsAssetStore

    var body: some View {
        Section {
            if assets.state == .downloading {
                AssetDownloadProgress(progress: assets.progress, preparing: assets.progress == nil)
            } else if assets.busy || assets.state == .checking {
                ProgressView()
            } else if assets.state == .ready {
                LabeledContent {
                    AssetSizeText(bytes: assets.installedBytes)
                } label: { Text("Total size") }
                    .accessibilityIdentifier("downloads-size-rulings")
                    .removeDownloadControl("Remove download", id: "downloads-remove-rulings") {
                        Task { await assets.remove() }
                    }
            } else {
                if assets.state == .incompatible {
                    Text("This download needs an update.")
                } else if assets.state == .failed {
                    Text("Unable to download. Please try again.")
                }
                AssetDownloadButton(pack: "rulings-v2", retry: assets.state == .failed || assets.state == .incompatible) {
                    Task { await assets.download() }
                }
                .accessibilityIdentifier("downloads-get-rulings")
            }
        } header: { Text("Rulings") }
            .alert("Unable to finish storage cleanup", isPresented: $assets.storageError) {
                Button("Try again") { Task { await assets.remove() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some files remain on this device. Please try again.")
            }
    }
}

private struct RulingsBrowser: View {
    let reader: RulingsReader
    @Environment(\.locale) private var locale
    @AppStorage("rulings.authority") private var authority = "sistani"
    @State private var search = RulingsSearchState()
    @State private var contents: [String: [RulingsSection]] = [:]
    @State private var counts: [String: Int] = [:]
    @State private var authorities: [RulingsAuthority] = []
    @State private var languages: [RulingsLanguage] = []
    @State private var submitted = ""
    @State private var query = ""
    @State private var failed = false
    @State private var loading = true
    @State private var retry = 0

    private var authorityName: String {
        authorities.first(where: { $0.id == authority }).map { locale.language.languageCode?.identifier == "ar" ? $0.arabic : $0.english } ?? authority
    }

    var body: some View {
        List {
            RulingsIntroSection()
            Section {
                Picker("Religious authority", selection: $authority) {
                    ForEach(authorities) { value in
                        Text(locale.language.languageCode?.identifier == "ar" ? value.arabic : value.english).tag(value.id)
                    }
                }
                .accessibilityIdentifier("rulings-authority")
            }
            if loading {
                ProgressView()
            } else if failed {
                Button("Try again") { retry += 1 }
            } else if submitted.isEmpty {
                ForEach(languages) { language in
                    if let sections = contents[language.id], !sections.isEmpty {
                        Section {
                            ForEach(sections) { section in
                                NavigationLink(section.title) {
                                    RulingsSectionView(reader: reader, authority: authority, authorityName: authorityName,
                                                       language: language, section: section)
                                }
                            }
                        } header: {
                            LabeledContent {
                                if let count = counts[language.id] {
                                    Text(count, format: .number)
                                }
                            } label: {
                                Text(language.name).accessibilityIdentifier("rulings-language-\(language.id)")
                            }
                        }
                    }
                }
            } else if search.failed {
                Button("Try again") { search.retry += 1 }
            } else if search.groups.isEmpty {
                if search.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            } else {
                if search.loading {
                    // Earlier results stay visible below until the next search replaces them.
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(search.groups) { group in
                    RulingsResults(reader: reader, authorityName: authorityName, language: group.language, query: submitted,
                                   questions: group.questions, header: group.language.name) { search.retry += 1 }
                }
            }
        }
        .navigationTitle("Rulings")
        .readingBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .searchHistory($query, area: .rulings)
        .submitsSearch($query, submitted: $submitted)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .task(id: [authority, submitted, String(search.retry), languages.map(\.id).joined(separator: ",")]) {
            guard !submitted.isEmpty, !languages.isEmpty else { search.clear(); return }
            await search.load(reader: reader, authority: authority, languages: languages, query: submitted)
        }
        .task(id: "\(authority)|\(locale.identifier)|\(retry)") {
            loading = true
            languages = []
            contents = [:]
            counts = [:]
            failed = false
            do {
                let choices = try await reader.authorities()
                let available = try await reader.languages(authority: authority)
                let totals = try await reader.questionCounts(authority: authority)
                var found: [String: [RulingsSection]] = [:]
                for language in available {
                    found[language.id] = try await reader.contents(authority: authority, language: language.id)
                }
                try Task.checkCancellation()
                authorities = choices
                // The app's language leads; the rest keep the pack's order.
                let preferred = RulingsReader.preferredLanguage(saved: nil, locale: locale.identifier, available: available)
                languages = available.filter { $0.id == preferred } + available.filter { $0.id != preferred }
                contents = found
                counts = totals
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                failed = true
            }
        }
    }
}

private struct RulingsResults: View {
    @AppStorage("showArabicDiacritics") private var showMarks = true
    let reader: RulingsReader
    let authorityName: String
    let language: RulingsLanguage
    var query = ""
    let questions: [Rulings]
    var loading = false
    var failed = false
    var header: String?
    let retry: () -> Void

    var body: some View {
        Section {
            if loading {
                ProgressView().frame(maxWidth: .infinity)
                rows(questions)
            } else if failed {
                Button("Try again", action: retry)
            } else {
                rows(questions)
                if questions.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            }
        } header: {
            if let header {
                LabeledContent {
                    // The count of rows shown; hidden until they've loaded.
                    if !loading, !failed {
                        Text(questions.count, format: .number)
                    }
                } label: {
                    Text(header)
                }
            }
        }
    }

    private func rows(_ values: [Rulings]) -> some View {
        ForEach(values) { value in
            NavigationLink {
                RulingsDetailView(reader: reader, rulings: value, authorityName: authorityName, language: language)
                    .recordSearchOnOpen(query, area: .rulings)
            } label: {
                VStack(alignment: .leading) {
                    if !value.context.isEmpty {
                        Text(value.context).font(.caption)
                    }
                    Text(showMarks ? value.preview : ArabicDisplay.plain(value.preview)).lineLimit(3)
                }
                .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
            }
            .accessibilityIdentifier("rulings-question-\(value.id.siteID)")
        }
    }
}

@MainActor @Observable private final class RulingsResultsState {
    var questions: [Rulings] = []
    var loading = true
    var failed = false
    var retry = 0

    func load(reader: RulingsReader, authority: String, language: String, section: RulingsSection) async {
        loading = true
        failed = false
        do {
            let found = try await reader.questions(authority: authority, language: language, section: section)
            try Task.checkCancellation()
            questions = found
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}

private struct RulingsGroup: Identifiable {
    let language: RulingsLanguage
    let questions: [Rulings]
    var id: String {
        language.id
    }
}

/// Searches every language of an authority, grouping matches by language.
@MainActor @Observable private final class RulingsSearchState {
    var groups: [RulingsGroup] = []
    var loading = false
    var failed = false
    var retry = 0
    private var loadedAuthority = ""

    func clear() {
        groups = []
        loading = false
        failed = false
    }

    func load(reader: RulingsReader, authority: String, languages: [RulingsLanguage], query: String) async {
        loading = true
        failed = false
        // Results from another authority shouldn't linger while the new ones load.
        if authority != loadedAuthority {
            groups = []
            loadedAuthority = authority
        }
        do {
            // Semantic matches lead each language, in ranked order; local matches fill in after them.
            var ranked: [String: [Rulings]] = [:]
            var seen: Set<Rulings.ID> = []
            do {
                guard let client = SemanticSearchClient.configured else { throw URLError(.unsupportedURL) }
                let codes = Set(languages.map(\.id))
                let results = try await client.search(query, kind: "rulings", sources: [authority], languages: languages.map(\.id))
                for result in results {
                    guard case let .rulings(source, code, id) = result.reference,
                          source == authority, codes.contains(code) else { continue }
                    let key = Rulings.ID(authority: source, language: code, siteID: id)
                    guard !seen.contains(key), let value = try await reader.question(key) else { continue }
                    seen.insert(key)
                    ranked[code, default: []].append(value)
                }
            } catch {
                try Task.checkCancellation()
                ranked = [:]
                seen = []
            }
            var found: [RulingsGroup] = []
            for language in languages {
                let local = try await reader.questions(authority: authority, language: language.id, query: query)
                let questions = (ranked[language.id] ?? []) + local.filter { !seen.contains($0.id) }
                if !questions.isEmpty {
                    found.append(RulingsGroup(language: language, questions: questions))
                }
            }
            try Task.checkCancellation()
            groups = found
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}

private struct RulingsSectionView: View {
    let reader: RulingsReader
    let authority: String
    let authorityName: String
    let language: RulingsLanguage
    let section: RulingsSection
    @State private var results = RulingsResultsState()

    @State private var children: [RulingsSection] = []

    var body: some View {
        List {
            ForEach(children) { child in
                NavigationLink(child.title) {
                    RulingsSectionView(reader: reader, authority: authority, authorityName: authorityName, language: language, section: child)
                }
            }
            if children.isEmpty || !results.questions.isEmpty {
                RulingsResults(reader: reader, authorityName: authorityName, language: language, questions: results.questions,
                               loading: results.loading, failed: results.failed,
                               header: String(localized: "Questions")) { results.retry += 1 }
            }
        }
        .navigationTitle(section.title)
        .readingBackground()
        .task(id: results.retry) {
            do { children = try await reader.contents(authority: authority, language: language.id, parent: section.id) }
            catch { results.failed = true; return }
            await results.load(reader: reader, authority: authority, language: language.id, section: section)
        }
    }
}

private struct RulingsDetailView: View {
    let reader: RulingsReader
    let rulings: Rulings
    let authorityName: String
    let language: RulingsLanguage
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var textSizePresented = false
    @State private var bookmarkFailed = false
    @State private var sections: [RulingsSection] = []
    @State private var notes: [RulingFootnote] = []
    @State private var expandedNotes: Set<RulingFootnote.ID> = []
    @State private var translationTarget: Locale.Language?
    var highlight: ReadingHighlight?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    segments(question, heading: 2)
                    if !rulings.answer.isEmpty {
                        segments(answer)
                    }
                }
                .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
                if let target = translationTarget {
                    let question = MachineTranslation.paragraphs(rulings.question)
                    MachineTranslationSection(source: Locale.Language(identifier: language.id), target: target, paragraphs: question + MachineTranslation.paragraphs(rulings.answer),
                                              headings: question.count, inList: true)
                        .id(rulings.id)
                }
                if !notes.isEmpty {
                    Section("Notes") {
                        ForEach(notes) { note in
                            DisclosureGroup(isExpanded: Binding {
                                expandedNotes.contains(note.id)
                            } set: { expanded in
                                if expanded {
                                    expandedNotes.insert(note.id)
                                } else {
                                    expandedNotes.remove(note.id)
                                }
                            }) {
                                segments(HighlightBlock(id: note.highlightBlock, plain: note.body))
                            } label: {
                                HStack {
                                    if note.chapter {
                                        Text("Chapter note")
                                    }
                                    Text(verbatim: note.label)
                                }
                            }
                        }
                    }
                    .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
                }
                details
            }
            .task(id: rulings.id) {
                if let found = try? await reader.footnotes(for: rulings.id), !Task.isCancelled {
                    notes = found
                    // Reveal the note a saved highlight points to.
                    expandedNotes = Set(found.filter { $0.highlightBlock == highlight?.block }.map(\.id))
                }
                // Long answers render lazily; bring the saved highlight's segment on screen before it focuses.
                let blocks = [question, answer] + notes.map { HighlightBlock(id: $0.highlightBlock, plain: $0.body) }
                if let block = blocks.first(where: { $0.id == highlight?.block }), let segment = block.segment(for: highlight), segment.id > 0 {
                    await Task.yield()
                    proxy.scrollTo("\(block.id):\(segment.id)", anchor: .top)
                }
                if let found = try? await reader.sections(for: rulings.id), !Task.isCancelled {
                    sections = found
                }
            }
        }
        .navigationTitle("Rulings")
        .readingBackground()
        .task(id: language.id) {
            translationTarget = await MachineTranslation.supportedTarget(from: Locale.Language(identifier: language.id))
        }
        .toolbar {
            Menu {
                ReadingSizeMenu(isPresented: $textSizePresented)
                ArabicDiacriticsToggle()
            } label: {
                Label("Reading options", systemImage: "textformat")
            }
            .accessibilityIdentifier("reading-options")
            .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
            BookmarkButton(source: rulings.id.siteID, isHadith: false, excerpt: rulings.preview,
                           reference: authorityName, ruling: rulings.id, failed: $bookmarkFailed)
                .appTip(.bookmarks)
        }
        .alert("Unable to save bookmark", isPresented: $bookmarkFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try again.") }
        .environment(\.focusedHighlight, highlight)
    }

    private var question: HighlightBlock {
        HighlightBlock(id: "question", plain: rulings.question)
    }

    private var answer: HighlightBlock {
        HighlightBlock(id: "answer", plain: rulings.answer)
    }

    @ViewBuilder private var details: some View {
        LabeledContent("Religious authority", value: authorityName)
        if let source = rulings.source {
            Link(destination: source) { Label("Source", systemImage: "arrow.up.right.square") }
        }
        if !sections.isEmpty {
            Section {
                ForEach(sections) { section in
                    NavigationLink {
                        RulingsSectionView(reader: reader, authority: rulings.id.authority, authorityName: authorityName, language: language, section: section)
                    } label: {
                        Label(section.title, systemImage: "tag")
                            .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
                    }
                    .accessibilityIdentifier("rulings-section-\(section.id)")
                }
            }
        }
    }

    private func segments(_ block: HighlightBlock, heading: Int? = nil) -> some View {
        ForEach(block.segments) { segment in
            HighlightText(text: segment.text, source: rulings.id.siteID, block: block.id, reference: authorityName,
                          arabic: language.id == "ar", ruling: rulings.id, heading: heading, blockText: block.text, offset: segment.offset)
                .id("\(block.id):\(segment.id)")
                // Segments of one passage read as continuous text.
                .listRowSeparator(segment.id == 0 ? .automatic : .hidden, edges: .top)
                .listRowSeparator(segment.id == block.segments.count - 1 ? .automatic : .hidden, edges: .bottom)
        }
    }
}

private struct RulingsIntroSection: View {
    var body: some View {
        Section {
            Label("This app is not a source of religious rulings. Refer to official sources.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rulings-notice")
            NavigationLink { RulingsSavedView() } label: { Label("Saved", systemImage: "bookmark") }
                .accessibilityIdentifier("rulings-saved")
        }
    }
}

private struct RulingsSavedView: View {
    @Environment(\.quranUserStore) private var store
    @Environment(\.rulingsAssets) private var assets
    @State private var availableHighlights: Set<String> = []

    private var highlights: [ReadingHighlight] {
        store?.highlights.filter { $0.ruling != nil } ?? []
    }

    var body: some View {
        Group {
            if store?.unavailable != false {
                ContentUnavailableView {
                    Label("Saved unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Your saved data could not be opened. Please try again.")
                } actions: {
                    Button("Try again") { store?.reopen() }
                }
            } else {
                SavedList(highlights: highlights, bookmarks: store?.bookmarks.filter { $0.kind == .ruling } ?? [],
                          canOpen: { $0.ruling != nil }, available: { availableHighlights.contains($0.id) })
                { entry in
                    if let id = entry.ruling {
                        SavedRulingDestination(id: id, highlight: entry.highlight)
                    }
                }
            }
        }
        .navigationTitle("Saved")
        .task(id: "\(assets?.revision ?? 0)|" + highlights.map { $0.id + String($0.modifiedAt.timeIntervalSince1970) }.joined(separator: "|")) {
            guard let assets, assets.state == .ready else { return }
            var available: Set<String> = []
            for (id, values) in Dictionary(grouping: highlights, by: { $0.ruling }) {
                guard let id, let ruling = try? await assets.reader.question(id) else { continue }
                var blocks = ["question": ruling.question, "answer": ruling.answer]
                if values.contains(where: { $0.block?.hasPrefix("note:") == true }) {
                    for note in await (try? assets.reader.footnotes(for: id)) ?? [] {
                        blocks[note.highlightBlock] = note.body
                    }
                }
                available.formUnion(values.filter { $0.isAvailable(in: blocks) }.map(\.id))
            }
            guard !Task.isCancelled else { return }
            availableHighlights = available
        }
    }
}

private struct SavedRulingDestination: View {
    let id: Rulings.ID
    var highlight: ReadingHighlight?
    @Environment(\.rulingsAssets) private var assets
    @Environment(\.locale) private var locale
    @State private var ruling: Rulings?
    @State private var language: RulingsLanguage?
    @State private var authorityName = ""
    @State private var loading = true
    @State private var retry = 0

    var body: some View {
        Group {
            if let assets, assets.state != .ready {
                List { RulingsDownloadSection(assets: assets) }
            } else if let assets, let ruling, let language {
                RulingsDetailView(reader: assets.reader, rulings: ruling, authorityName: authorityName, language: language, highlight: highlight)
            } else if loading {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("Saved passage unavailable", systemImage: "exclamationmark.triangle")
                } actions: { Button("Try again") { retry += 1 } }
            }
        }
        .task(id: "\(assets?.revision ?? 0)|\(retry)|\(locale.identifier)") {
            guard let assets, assets.state == .ready else { loading = false; return }
            loading = true
            ruling = nil
            language = nil
            do {
                let found = try await assets.reader.question(id)
                let languages = try await assets.reader.languages(authority: id.authority)
                let authorities = try await assets.reader.authorities()
                try Task.checkCancellation()
                ruling = found
                language = languages.first { $0.id == id.language }
                let authority = authorities.first { $0.id == id.authority }
                authorityName = (locale.language.languageCode?.identifier == "ar" ? authority?.arabic : authority?.english) ?? id.authority
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
            }
        }
    }
}
