import SwiftUI

enum FigureRoute: Hashable {
    case browser
    case profile(String)
    case tree(String)
    case observance(eventID: String, figureIDs: [String])
    case hadith
    case supplications
}

struct FigureBrowser: View {
    @Environment(\.locale) private var locale
    @State private var library: Result<FigureLibrary, any Error>?
    @State private var query = ""

    var body: some View {
        Group {
            switch library {
            case let .success(library):
                let matches = library.search(query, locale: locale)
                List {
                    ForEach(FigureGroup.allCases, id: \.self) { group in
                        let people = matches.filter { FigureGroup.group(for: $0.id) == group }
                        if !people.isEmpty {
                            Section {
                                ForEach(people) { person in
                                    NavigationLink(value: FigureRoute.profile(person.id)) {
                                        Text(verbatim: person.title(locale))
                                    }
                                    .accessibilityIdentifier("figure-\(person.id)")
                                }
                            }
                        }
                    }
                }
                .searchable(text: $query)
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView("No figures found", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
            case .failure:
                ContentUnavailableView("Figures unavailable", systemImage: "exclamationmark.triangle")
            case nil:
                ProgressView()
            }
        }
        .navigationTitle("Figures")
        .task {
            library = await FigureFeed.shared.load()
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
            library = await FigureFeed.shared.load()
        }
    }
}

extension View {
    func figureDestinations(hadithAssets: HadithAssetStore? = nil, supplicationAssets: HadithAssetStore? = nil) -> some View {
        navigationDestination(for: FigureRoute.self) { route in
            switch route {
            case .browser: FigureBrowser()
            case let .profile(id): FigureDestination(id: id)
            case let .tree(id): FigureDestination(id: id, showsTree: true)
            case let .observance(_, figureIDs): ObservanceFigurePicker(figureIDs: figureIDs)
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
                  let library = try? await FigureFeed.shared.load().get() else { return }
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
            library = await FigureFeed.shared.load()
        }
    }
}

enum FigureGroup: CaseIterable {
    case infallibles, prophets, companions, other

    static func group(for id: String) -> Self {
        if infallibleIDs.contains(id) {
            return .infallibles
        }
        if id.hasPrefix("prophet-") {
            return .prophets
        }
        if companionIDs.contains(id) {
            return .companions
        }
        return .other
    }

    private static let infallibleIDs: Set<String> = [
        "prophet-muhammad", "fatima-al-zahra", "ali-ibn-abi-talib", "hasan-ibn-ali",
        "husayn-ibn-ali", "ali-zayn-al-abidin", "muhammad-al-baqir", "jafar-al-sadiq",
        "musa-al-kadhim", "ali-al-ridha", "muhammad-al-jawad", "ali-al-hadi",
        "hasan-al-askari", "muhammad-al-mahdi",
    ]
    private static let companionIDs: Set<String> = [
        "salman-al-muhammadi", "abu-dharr-al-ghifari", "miqdad-ibn-al-aswad", "ammar-ibn-yasir",
    ]
}
