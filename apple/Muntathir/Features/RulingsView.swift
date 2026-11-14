import SwiftUI

struct RulingsView: View {
    @Environment(\.rulingsAssets) private var assets

    var body: some View {
        if let assets {
            if assets.state == .ready {
                RulingsBrowser(reader: assets.reader)
                    .id(assets.revision)
            } else {
                List { RulingsDownloadSection(assets: assets) }
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove download", systemImage: "trash", role: .destructive) {
                            Task { await assets.remove() }
                        }
                        .accessibilityIdentifier("downloads-remove-rulings")
                    }
            } else {
                if assets.state == .incompatible {
                    Text("This download needs an update.")
                } else if assets.state == .failed {
                    Text("Unable to download. Please try again.")
                }
                AssetDownloadButton(pack: "rulings", retry: assets.state == .failed || assets.state == .incompatible) {
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
    @AppStorage("rulings.languages") private var savedLanguages = Data()
    @State private var results = RulingsResultsState()
    @State private var authorities: [RulingsAuthority] = []
    @State private var languages: [RulingsLanguage] = []
    @State private var language = ""
    @State private var query = ""
    @State private var failed = false
    @State private var loading = true
    @State private var retry = 0

    private var languagePreferences: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: savedLanguages)) ?? [:]
    }

    var body: some View {
        List {
            Section {
                Picker("Religious authority", selection: $authority) {
                    ForEach(authorities) { value in
                        Text(locale.language.languageCode?.identifier == "ar" ? value.arabic : value.english).tag(value.id)
                    }
                }
                .accessibilityIdentifier("rulings-authority")
                if !loading {
                    Picker("Language", selection: $language) {
                        Text("Choose a language").tag("")
                        ForEach(languages) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("rulings-language")
                }
            }
            if loading {
                ProgressView()
            } else if failed {
                Button("Try again") { retry += 1 }
            } else if let selected = languages.first(where: { $0.id == language }) {
                RulingsResults(reader: reader, authority: authority, authorityName: authorities.first(where: { $0.id == authority }).map { locale.language.languageCode?.identifier == "ar" ? $0.arabic : $0.english } ?? authority, language: selected, query: query, state: results)
            } else {
                Text("Choose a language")
            }
        }
        .navigationTitle("Rulings")
        .readingBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .searchHistory(query, area: .rulings)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .task(id: [authority, language, query, String(results.retry)]) {
            guard !language.isEmpty else { return }
            await results.load(reader: reader, authority: authority, language: language, query: query, topic: nil)
        }
        .onChange(of: language) { _, value in
            guard !value.isEmpty else { return }
            var preferences = languagePreferences
            preferences[authority] = value
            if let data = try? JSONEncoder().encode(preferences) { savedLanguages = data }
        }
        .task(id: "\(authority)|\(locale.identifier)|\(retry)") {
            loading = true
            language = ""
            languages = []
            failed = false
            do {
                let choices = try await reader.authorities()
                let available = try await reader.languages(authority: authority)
                try Task.checkCancellation()
                authorities = choices
                languages = available
                language = RulingsReader.preferredLanguage(saved: languagePreferences[authority], locale: locale.identifier, available: available) ?? ""
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
    let reader: RulingsReader
    let authority: String
    let authorityName: String
    let language: RulingsLanguage
    var query = ""
    var topic: RulingsTopic?
    let state: RulingsResultsState

    var body: some View {
        Section {
            if state.loading {
                ProgressView()
            } else if state.failed {
                Button("Try again") { state.retry += 1 }
            } else {
                ForEach(state.topics.filter { $0.parent == topic?.id }) { child in
                    NavigationLink {
                        RulingsTopicView(reader: reader, authority: authority, authorityName: authorityName, language: language, topic: child)
                    } label: {
                        Text(child.title)
                            .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
                    }
                }
                rows(state.questions)
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MeaningSearchResults(query: query, hasLocalResults: !state.questions.isEmpty, search: {
                        guard let client = SemanticSearchClient.configured else { throw URLError(.unsupportedURL) }
                        let results = try await client.search(query, kind: "rulings", sources: [authority], languages: [language.id])
                        var found: [Rulings] = []
                        var seen: Set<Rulings.ID> = []
                        for result in results {
                            guard case let .rulings(source, code, id) = result.reference,
                                  source == authority, code == language.id else { throw HadithDatabaseError.invalidReference }
                            let key = Rulings.ID(authority: source, language: code, siteID: id)
                            guard let value = try await reader.question(key) else { throw HadithDatabaseError.incompatible }
                            if seen.insert(key).inserted { found.append(value) }
                        }
                        return found
                    }) { rows($0) }
                    .id([authority, language.id, query])
                } else if !state.topics.contains(where: { $0.parent == topic?.id }) && state.questions.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private func rows(_ values: [Rulings]) -> some View {
        ForEach(values) { value in
            NavigationLink {
                RulingsDetailView(rulings: value, authorityName: authorityName, language: language)
                    .recordSearchOnOpen(query, area: .rulings)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(value.question).font(.headline).lineLimit(3)
                    Text(value.answer).foregroundStyle(.secondary).lineLimit(2)
                }
                .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
            }
            .accessibilityIdentifier("rulings-question-\(value.id.siteID)")
        }
    }
}

@MainActor @Observable private final class RulingsResultsState {
    var topics: [RulingsTopic] = []
    var questions: [Rulings] = []
    var loading = true
    var failed = false
    var retry = 0

    func load(reader: RulingsReader, authority: String, language: String, query: String, topic: RulingsTopic?) async {
        loading = true
        failed = false
        do {
            if !query.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
            let browsing = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let foundTopics = browsing ? try await reader.topics(authority: authority, language: language) : []
            let foundQuestions = !browsing || topic != nil ? try await reader.questions(authority: authority, language: language, query: query, topic: topic?.id) : []
            try Task.checkCancellation()
            topics = foundTopics
            questions = foundQuestions
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            loading = false
        }
    }
}

private struct RulingsTopicView: View {
    let reader: RulingsReader
    let authority: String
    let authorityName: String
    let language: RulingsLanguage
    let topic: RulingsTopic
    @State private var results = RulingsResultsState()

    var body: some View {
        List {
            RulingsResults(reader: reader, authority: authority, authorityName: authorityName, language: language, topic: topic, state: results)
        }
        .navigationTitle(topic.title)
        .readingBackground()
        .task(id: results.retry) {
            await results.load(reader: reader, authority: authority, language: language.id, query: "", topic: topic)
        }
    }
}

private struct RulingsDetailView: View {
    let rulings: Rulings
    let authorityName: String
    let language: RulingsLanguage
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var textSizePresented = false

    var body: some View {
        List {
            Section {
                Text(rulings.question).readingText(arabic: language.id == "ar", hadith: true, heading: 2).textSelection(.enabled)
                if !rulings.answer.isEmpty {
                    Text(rulings.answer).readingText(arabic: language.id == "ar", hadith: true).textSelection(.enabled)
                }
            }
            .environment(\.layoutDirection, language.rightToLeft ? .rightToLeft : .leftToRight)
            LabeledContent("Religious authority", value: authorityName)
            if let source = rulings.source {
                Link(destination: source) { Label("Source", systemImage: "arrow.up.right.square") }
            }
        }
        .navigationTitle("Rulings")
        .readingBackground()
        .toolbar { ReadingSizeMenu(isPresented: $textSizePresented) }
        .readingSizePresentation(isPresented: $textSizePresented, compact: sizeClass != .regular)
    }
}
