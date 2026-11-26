import AppIntents

// Intent type names are saved in people's shortcuts; never rename one.

/// Where each opened entity lands. Shared by the iOS 26 intents and their iOS 27 schema twins.
enum IntentOpen {
    @MainActor static func surah(_ surah: SurahEntity) {
        IntentRouter.shared.pending = .tool(.quran, path: [.quran(.surah(surah.id))])
    }

    @MainActor static func ayah(_ ayah: AyahEntity) {
        IntentRouter.shared.pending = .tool(.quran, path: [.quran(.verse(surah: ayah.surah, verse: ayah.verse, query: ""))])
    }

    @MainActor static func figure(_ figure: FigureEntity) {
        IntentRouter.shared.pending = .tool(.figures, path: [.profile(figure.id)])
    }

    /// Matches tapping the event in Events: one person opens their profile, several offer a choice.
    static func event(_ event: IslamicEventEntity) async {
        let library = try? await FigureStore.shared.load().get()
        let figureIDs = event.figureIDs.filter { library?.byID[$0] != nil }
        let path: [FigureRoute] = switch figureIDs.count {
        case 0: []
        case 1: [.profile(figureIDs[0])]
        default: [.observance(eventID: event.id, figureIDs: figureIDs)]
        }
        await MainActor.run { IntentRouter.shared.pending = .tool(.events, path: path) }
    }

    @MainActor static func hadith(_ hadith: HadithEntity) throws {
        guard let source = HadithSource(key: hadith.id) else { throw MuntathirIntentError.notFound }
        IntentRouter.shared.pending = .hadith(source)
    }

    static func supplication(_ supplication: SupplicationEntity) async throws {
        guard let source = HadithSource(key: supplication.id) else { throw MuntathirIntentError.notFound }
        let reader = try await PackAccess.supplications()
        guard let id = try await reader.resolve(source) else { throw MuntathirIntentError.notFound }
        await MainActor.run { IntentRouter.shared.pending = .tool(.supplications, path: [.supplication(id: id, query: "")]) }
    }

    @MainActor static func ruling(_ ruling: RulingEntity) throws {
        guard let id = Rulings.ID(key: ruling.id) else { throw MuntathirIntentError.notFound }
        IntentRouter.shared.pending = .tool(.rulings, path: [.rulings(.question(id))])
    }

    @MainActor static func search(_ term: String, in area: SearchArea?) {
        IntentRouter.shared.pending = .search((area ?? .quran).tool, term)
    }
}

// MARK: - iOS 26

// Plain intents: each entity type may have only one `OpenIntent`, and on iOS 27 that's the schema twin.

struct OpenSurahIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Surah"
    @Parameter(title: "Surah") var target: SurahEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.surah(target)
        return .result()
    }
}

struct OpenAyahIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Ayah"
    @Parameter(title: "Ayah") var target: AyahEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.ayah(target)
        return .result()
    }
}

struct OpenFigureIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Figure"
    @Parameter(title: "Figure") var target: FigureEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.figure(target)
        return .result()
    }
}

struct OpenIslamicEventIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Islamic Event"
    @Parameter(title: "Event") var target: IslamicEventEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.event(target)
        return .result()
    }
}

struct OpenHadithIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Hadith"
    @Parameter(title: "Hadith") var target: HadithEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.hadith(target)
        return .result()
    }
}

struct OpenSupplicationIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Supplication"
    @Parameter(title: "Supplication") var target: SupplicationEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.supplication(target)
        return .result()
    }
}

struct OpenRulingIntent: AppIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let title: LocalizedStringResource = "Open Ruling"
    @Parameter(title: "Ruling") var target: RulingEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.ruling(target)
        return .result()
    }
}

/// Tools aren't entities, so this one has no `system.open` twin.
struct OpenToolIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Tool"
    static let description = IntentDescription("Opens a tool in Muntathir, such as the Quran or Qibla.")

    @Parameter(title: "Tool") var target: AppTool

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor func perform() async throws -> some IntentResult {
        guard target.isAvailable else { throw MuntathirIntentError.unavailableOnThisDevice }
        IntentRouter.shared.pending = .tool(target)
        return .result()
    }
}

struct SearchInAppIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search in Muntathir"
    static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Search") var criteria: StringSearchCriteria
    @Parameter(title: "Area") var area: SearchArea?

    func perform() async throws -> some IntentResult {
        await IntentOpen.search(criteria.term, in: area)
        return .result()
    }
}

// MARK: - iOS 27 Apple Intelligence schemas

// Hidden from Shortcuts so people don't see each action twice; the iOS 26 intents keep serving Shortcuts and App Shortcuts.

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenSurahSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: SurahEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.surah(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenAyahSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: AyahEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.ayah(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenFigureSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: FigureEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.figure(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenIslamicEventSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: IslamicEventEntity

    func perform() async throws -> some IntentResult {
        await IntentOpen.event(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenHadithSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: HadithEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.hadith(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenSupplicationSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: SupplicationEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.supplication(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.open)
struct OpenRulingSchemaIntent: OpenIntent {
    static let isAssistantOnly = true
    var target: RulingEntity

    func perform() async throws -> some IntentResult {
        try await IntentOpen.ruling(target)
        return .result()
    }
}

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.searchInApp)
struct SearchInAppSchemaIntent: ShowInAppSearchResultsIntent {
    static let isAssistantOnly = true
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    func perform() async throws -> some IntentResult {
        await IntentOpen.search(criteria.term, in: nil)
        return .result()
    }
}
