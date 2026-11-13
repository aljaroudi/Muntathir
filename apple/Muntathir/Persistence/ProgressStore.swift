import Foundation
import Observation
import SwiftData
import SwiftUI

@Model final class PrayerHistoryRecord {
    var sessionID: UUID = UUID()
    var payload: Data = Data()

    init(_ completion: PrayerCompletion) throws {
        sessionID = completion.id
        payload = try JSONEncoder().encode(completion)
    }
}

@Model final class ProgressActivityRecord {
    var activityID: UUID = UUID()
    var payload: Data = Data()

    init(_ activity: ProgressActivity) throws {
        activityID = activity.id
        payload = try JSONEncoder().encode(activity)
    }
}

@MainActor @Observable final class ProgressStore {
    private(set) var container: ModelContainer?
    private(set) var records: [PrayerCompletion] = []
    private(set) var activities: [ProgressActivity] = []
    private(set) var pendingActivities: [ProgressActivity] = []
    private(set) var pending: [PrayerCompletion] = []
    private(set) var unavailable = false
    @ObservationIgnored private let configuration: ModelConfiguration
    @ObservationIgnored private let saveContext: (ModelContext) throws -> Void

    init(configuration: ModelConfiguration, saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.configuration = configuration
        self.saveContext = saveContext
        reopen()
    }

    static func application() -> ProgressStore {
        let arguments = ProcessInfo.processInfo.arguments
        let schema = Schema([PrayerHistoryRecord.self, ProgressActivityRecord.self])
        if arguments.contains("--ui-testing") {
            let directory = URL.applicationSupportDirectory.appending(path: "PrayerHistoryUITests", directoryHint: .isDirectory)
            if !arguments.contains("--ui-testing-preserve-state") {
                try? FileManager.default.removeItem(at: directory)
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = ProgressStore(configuration: ModelConfiguration("PrayerHistoryUITests", schema: schema, url: directory.appending(path: "prayers.store"), cloudKitDatabase: .none))
            #if DEBUG
                if arguments.contains("--ui-testing-progress-fixture"), !arguments.contains("--ui-testing-preserve-state") {
                    for (kind, amount) in [(ProgressActivityKind.quranReading, 2700.0), (.hadithReading, 1200), (.supplicationReading, 420), (.tasbih, 1234)] {
                        store.saveActivity(ProgressActivity(kind: kind, amount: amount))
                    }
                    let location = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh")
                    for (index, prayer) in PrayerProgress.prayers.enumerated() {
                        for offset in 0 ... index {
                            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: .now)!
                            if let athan = PrayerCalculator.times(on: day, location: location, method: .jafari).first(where: { $0.name == prayer })?.date {
                                store.save(PrayerProgress.snapshot(prayer: prayer, at: athan, location: location, method: .jafari))
                            }
                        }
                    }
                }
            #endif
            return store
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return ProgressStore(configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        return ProgressStore(configuration: ModelConfiguration("PrayerHistory", schema: schema, cloudKitDatabase: .private("iCloud.com.aljaroudi.Muntathir")))
    }

    func reopen() {
        do {
            let opened = try ModelContainer(for: PrayerHistoryRecord.self, ProgressActivityRecord.self, configurations: configuration)
            opened.mainContext.autosaveEnabled = false
            container = opened
            try receive(opened.mainContext.fetch(FetchDescriptor<PrayerHistoryRecord>()).map(\.payload))
            try receiveActivities(opened.mainContext.fetch(FetchDescriptor<ProgressActivityRecord>()).map(\.payload))
            unavailable = false
        } catch { unavailable = true }
    }

    func receive(_ payloads: [Data]) {
        records = payloads.compactMap { try? JSONDecoder().decode(PrayerCompletion.self, from: $0) }
    }

    func receiveActivities(_ payloads: [Data]) {
        activities = payloads.compactMap { try? JSONDecoder().decode(ProgressActivity.self, from: $0) }.filter(\.isValid)
    }

    func saveActivity(_ activity: ProgressActivity) {
        guard activity.isValid else { return }
        if let index = pendingActivities.firstIndex(where: { $0.id == activity.id }) {
            if pendingActivities[index].amount < activity.amount {
                pendingActivities[index] = activity
            }
        } else {
            pendingActivities.append(activity)
        }
        retry()
    }

    func save(_ completion: PrayerCompletion) {
        if !pending.contains(where: { $0.id == completion.id }) {
            pending.append(completion)
        }
        retry()
    }

    func retry() {
        if container == nil {
            reopen()
        }
        guard let context = container?.mainContext else { return }
        do {
            let existing = try context.fetch(FetchDescriptor<PrayerHistoryRecord>())
            var saved = Set(existing.map(\.sessionID))
            for completion in pending where saved.insert(completion.id).inserted {
                try context.insert(PrayerHistoryRecord(completion))
            }
            for activity in pendingActivities {
                let id = activity.id
                let matches = try context.fetch(FetchDescriptor<ProgressActivityRecord>(predicate: #Predicate { $0.activityID == id }))
                if let row = matches.first {
                    let previous = try JSONDecoder().decode(ProgressActivity.self, from: row.payload)
                    if previous.amount < activity.amount {
                        row.payload = try JSONEncoder().encode(activity)
                    }
                } else {
                    try context.insert(ProgressActivityRecord(activity))
                }
            }
            try saveContext(context)
            pending.removeAll()
            pendingActivities.removeAll()
            try receive(context.fetch(FetchDescriptor<PrayerHistoryRecord>()).map(\.payload))
            try receiveActivities(context.fetch(FetchDescriptor<ProgressActivityRecord>()).map(\.payload))
            unavailable = false
        } catch {
            context.rollback()
            unavailable = true
        }
    }
}

extension EnvironmentValues {
    @Entry var progressStore: ProgressStore? = nil
}

struct ProgressDataView<Content: View>: View {
    let store: ProgressStore
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if let container = store.container {
                ProgressObserver(store: store) { content }.modelContainer(container)
            } else {
                content
            }
        }
        .environment(\.progressStore, store)
    }
}

private struct ProgressObserver<Content: View>: View {
    let store: ProgressStore
    @ViewBuilder let content: Content
    @Query private var rows: [PrayerHistoryRecord]
    @Query private var activities: [ProgressActivityRecord]

    var body: some View {
        content.onChange(of: rows.map(\.payload), initial: true) { _, payloads in store.receive(payloads) }
            .onChange(of: activities.map(\.payload), initial: true) { _, payloads in store.receiveActivities(payloads) }
    }
}
