import Foundation
import Observation
import SwiftData

@MainActor @Observable final class QuranUserStore {
    private(set) var container: ModelContainer?
    private(set) var states: [String: QuranVerseState] = [:]
    private(set) var unavailable = false
    @ObservationIgnored private let configuration: ModelConfiguration
    @ObservationIgnored private var installationID: String
    @ObservationIgnored private let saveContext: (ModelContext) throws -> Void

    init(configuration: ModelConfiguration, installationID: String, saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.configuration = configuration
        self.installationID = installationID
        self.saveContext = saveContext
        reopen()
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: QuranUserSchemaV1.self), migrationPlan: QuranUserMigrationPlan.self, configurations: [configuration])
    }

    static func application() -> QuranUserStore {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        let unitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let defaults = UserDefaults(suiteName: "Muntathir.UITests")!
        let installationID = defaults.string(forKey: "quranInstallationID") ?? UUID().uuidString
        if testing {
            defaults.set(installationID, forKey: "quranInstallationID")
        }
        let schema = Schema(versionedSchema: QuranUserSchemaV1.self)
        if testing {
            let directory = URL.applicationSupportDirectory.appending(path: "QuranUITests", directoryHint: .isDirectory)
            // Only an explicitly requested UI-test reset removes this isolated test store.
            if !arguments.contains("--ui-testing-preserve-state") {
                try? FileManager.default.removeItem(at: directory)
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "annotations.store")
            return QuranUserStore(configuration: ModelConfiguration("QuranUITests", schema: schema, url: url, cloudKitDatabase: .none), installationID: installationID) { context in
                if arguments.contains("--ui-testing-quran-save-failure") {
                    throw QuranUserStoreError.unavailable
                }
                try context.save()
            }
        }
        if unitTesting {
            return QuranUserStore(configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none), installationID: installationID)
        }
        return QuranUserStore(configuration: ModelConfiguration("QuranPersonal", schema: schema, cloudKitDatabase: .private("iCloud.com.aljaroudi.Muntathir")), installationID: "")
    }

    static func localInstallationID(directory: URL = URL.applicationSupportDirectory.appending(path: "QuranIdentity", directoryHint: .isDirectory)) throws -> String {
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A restored backup must not let two devices edit the same installation's sync records.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let file = directory.appending(path: "installation-id")
        if FileManager.default.fileExists(atPath: file.path) {
            let value = try String(contentsOf: file, encoding: .utf8)
            guard UUID(uuidString: value) != nil else { throw QuranUserStoreError.unavailable }
            return value
        }
        let value = UUID().uuidString
        try Data(value.utf8).write(to: file, options: .atomic)
        return value
    }

    func reopen() {
        do {
            if installationID.isEmpty {
                installationID = try Self.localInstallationID()
            }
            let opened = try Self.makeContainer(configuration: configuration)
            opened.mainContext.autosaveEnabled = false
            let rows = try opened.mainContext.fetch(FetchDescriptor<QuranAnnotation>())
            container = opened
            receive(rows.map(QuranAnnotationSnapshot.init))
            unavailable = false
        } catch {
            container = nil
            unavailable = true
        }
    }

    func receive(_ rows: [QuranAnnotationSnapshot]) {
        states = QuranVerseState.resolve(rows)
    }

    func state(for verseID: String) -> QuranVerseState {
        states[verseID] ?? QuranVerseState(id: verseID)
    }

    func setFavorite(_ value: Bool, for verseID: String, now: Date = .now) throws {
        try update(verseID: verseID) { row in
            row.isFavorite = value
            row.favoriteModifiedAt = max(now, state(for: verseID).favoriteModifiedAt.addingTimeInterval(0.001))
        }
    }

    func setNote(_ value: String, for verseID: String, now: Date = .now) throws {
        try update(verseID: verseID) { row in
            row.note = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value
            row.noteModifiedAt = max(now, state(for: verseID).noteModifiedAt.addingTimeInterval(0.001))
        }
    }

    private func refresh(_ verseID: String, in context: ModelContext) throws -> [QuranAnnotation] {
        let rows = try context.fetch(FetchDescriptor<QuranAnnotation>(predicate: #Predicate { $0.verseID == verseID }))
        states[verseID] = QuranVerseState.resolve(rows.map(QuranAnnotationSnapshot.init))[verseID]
        return rows
    }

    private func update(verseID: String, mutation: (QuranAnnotation) -> Void) throws {
        guard let context = container?.mainContext else { throw QuranUserStoreError.unavailable }
        let installation = installationID
        do {
            // Imported state may have changed since the menu or editor opened.
            let rows = try refresh(verseID, in: context)
            let local = rows.filter { $0.verseID == verseID && $0.installationID == installation }
                .sorted { $0.recordID < $1.recordID }
            let row: QuranAnnotation
            if let existing = local.first {
                row = existing
            } else {
                row = QuranAnnotation(verseID: verseID, installationID: installation)
                context.insert(row)
            }
            mutation(row)
            try saveContext(context)
            _ = try refresh(verseID, in: context)
        } catch {
            context.rollback()
            _ = try? refresh(verseID, in: context)
            throw error
        }
    }
}

enum QuranUserStoreError: Error { case unavailable }
