import SwiftUI

enum FigureRoute: Hashable {
    case tool(AppTool)
    case browser
    case profile(String)
    case tree(String)
    case observance(eventID: String, figureIDs: [String])
    case hadith
    case supplications
    case sermon(id: String, title: String, speakerID: String)
}

struct FigureBrowser: View {
    @Environment(\.locale) private var locale
    @State private var library: Result<FigureLibrary, any Error>?
    @State private var query = ""

    @State private var submitted = ""
    @State private var remote: [FigureLibrary.BrowserSection]?
    /// Local matches for `submitted`, filtered once per search instead of on every render.
    @State private var local: [FigureLibrary.BrowserSection] = []

    private struct LocalFilter: Equatable {
        let query: String
        let locale: Locale
        let loaded: Bool
    }

    private func refreshLocalMatches() {
        guard case let .success(library) = library else { return }
        local = library.browserSections(matching: submitted, locale: locale)
    }

    var body: some View {
        Group {
            switch library {
            case let .success(library):
                let sections = remote ?? local
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.figures) { person in
                                NavigationLink {
                                    FigureProfile(figure: person, library: library)
                                        .recordSearchOnOpen(submitted, area: .figures)
                                } label: {
                                    Text(verbatim: person.title(locale))
                                }
                                .accessibilityIdentifier("figure-\(person.id)")
                            }
                        }
                    }
                }
                .task(id: submitted) {
                    // Reset here rather than in onChange, which can run after a fast search has already finished.
                    remote = nil
                    guard !submitted.isEmpty, let client = SemanticSearchClient.configured else { return }
                    do {
                        let hits = try await client.search(submitted, kind: "figure")
                        let figures = hits.compactMap { hit -> Figure? in
                            guard case let .figure(id) = hit.reference else { return nil }
                            return library.byID[id]
                        }
                        try Task.checkCancellation()
                        if hits.isEmpty {
                            remote = []
                        } else if !figures.isEmpty {
                            remote = [.init(id: "results", figures: figures)]
                        }
                    } catch {
                        if !Task.isCancelled {
                            remote = nil
                        }
                    }
                }
                .overlay {
                    if sections.isEmpty {
                        ContentUnavailableView("No figures found", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
            case .failure:
                ContentUnavailableView("Figures unavailable", systemImage: "exclamationmark.triangle")
            case nil:
                ProgressView()
            }
        }
        .searchable(text: $query, placement: .alwaysVisible)
        .searchHistory($query, area: .figures)
        .submitsSearch($query, submitted: $submitted)
        .onChange(of: LocalFilter(query: submitted, locale: locale, loaded: library != nil), initial: true) { refreshLocalMatches() }
        .navigationTitle("Figures")
        .task {
            library = await FigureStore.shared.load()
        }
    }
}

struct FigureDestination: View {
    let id: String
    var showsTree = false
    @State private var library: Result<FigureLibrary, any Error>?

    var body: some View {
        Group {
            switch library {
            case let .success(library):
                if let figure = library.byID[id] {
                    if showsTree {
                        FigureFamilyTree(originalID: id, library: library)
                    } else {
                        FigureProfile(figure: figure, library: library)
                            .id(figure.id)
                    }
                } else {
                    ContentUnavailableView("Figures unavailable", systemImage: "exclamationmark.triangle")
                }
            case .failure:
                ContentUnavailableView("Figures unavailable", systemImage: "exclamationmark.triangle")
            case nil:
                ProgressView()
            }
        }
        .task {
            library = await FigureStore.shared.load()
        }
    }
}

extension View {
    func figureDestinations(hadithAssets: HadithAssetStore? = nil, supplicationAssets: HadithAssetStore? = nil) -> some View {
        navigationDestination(for: FigureRoute.self) { route in
            switch route {
            case let .tool(tool): ToolDestination(tool: tool)
            case .browser: FigureBrowser()
            case let .profile(id): FigureDestination(id: id)
            case let .tree(id): FigureDestination(id: id, showsTree: true)
            case let .observance(_, figureIDs): ObservanceFigurePicker(figureIDs: figureIDs)
            case let .sermon(id, title, speakerID): SermonDestination(id: id, title: title, speakerID: speakerID)
            case .hadith:
                if let hadithAssets {
                    HadithLibraryView(assets: hadithAssets)
                }
            case .supplications:
                if let supplicationAssets {
                    HadithLibraryView(assets: supplicationAssets, supplications: true)
                        .environment(\.hadithAssets, supplicationAssets)
                        .environment(\.hadithSession, nil)
                }
            }
        }
    }
}

struct FigureObservanceRow: View {
    @Environment(\.locale) private var locale
    @State private var ids: [String] = []
    let event: IslamicEvent

    var body: some View {
        Group {
            if ids.count == 1, let id = ids.first {
                NavigationLink(value: FigureRoute.profile(id)) { label }
                    .accessibilityIdentifier("observance-\(event.id)")
            } else if ids.count > 1 {
                NavigationLink(value: FigureRoute.observance(eventID: event.id, figureIDs: ids)) { label }
                    .accessibilityIdentifier("observance-\(event.id)")
            } else {
                label
            }
        }
        .task(id: event.figureIDs) {
            ids = []
            guard !event.figureIDs.isEmpty,
                  let library = try? await FigureStore.shared.load().get() else { return }
            ids = event.figureIDs.filter { library.byID[$0] != nil }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: event.title(locale: locale)).font(.body)
            if let year = event.yearText(locale: locale) {
                Text(verbatim: year).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ObservanceFigurePicker: View {
    @Environment(\.locale) private var locale
    @State private var library: Result<FigureLibrary, any Error>?
    let figureIDs: [String]

    var body: some View {
        Group {
            switch library {
            case let .success(library):
                List(figureIDs.compactMap { library.byID[$0] }) { figure in
                    NavigationLink(value: FigureRoute.profile(figure.id)) {
                        Text(verbatim: figure.title(locale))
                    }
                    .accessibilityIdentifier("figure-\(figure.id)")
                }
            case .failure:
                ContentUnavailableView("Figures unavailable", systemImage: "exclamationmark.triangle")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle("Figures")
        .task {
            library = await FigureStore.shared.load()
        }
    }
}
