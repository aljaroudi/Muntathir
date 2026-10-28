import Foundation
import Observation
import WidgetKit

struct Preferences: Codable, Equatable, Sendable {
    var savedLocation: SavedLocation?
    var prayerMethod: PrayerMethod = .tehran
    var imsakMinutes = 10
    var enabledPrayers: Set<PrayerName> = [.fajr, .dhuhr, .maghrib]
    var showFeelsLikeTemperature = false
    var announcementNotifications = false
    var timeSensitiveNotifications = true
    var prayerSounds: [String: PrayerAlertSound] = [:]

    func sound(for prayer: PrayerName) -> PrayerAlertSound {
        prayerSounds[prayer.rawValue] ?? .chime
    }

    var selectedSourceID: String? = CalendarSource.middleEast
    var monthOffsets: [MonthOffset] = []
    var hiddenPrayers: Set<PrayerName> = []
    func isVisible(_ prayer: PrayerName) -> Bool {
        prayer.isVisible(hidden: hiddenPrayers)
    }

    enum CodingKeys: String, CodingKey {
        case timeSensitiveNotifications, prayerSounds
        case showFeelsLikeTemperature, savedLocation, prayerMethod, imsakMinutes, enabledPrayers, announcementNotifications, selectedSourceID, monthOffsets, hiddenPrayers
    }

    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showFeelsLikeTemperature = try c.decodeIfPresent(Bool.self, forKey: .showFeelsLikeTemperature) ?? false
        savedLocation = try c.decodeIfPresent(SavedLocation.self, forKey: .savedLocation)
        prayerMethod = try c.decodeIfPresent(PrayerMethod.self, forKey: .prayerMethod) ?? .tehran
        imsakMinutes = try min(120, max(0, c.decodeIfPresent(Int.self, forKey: .imsakMinutes) ?? 10))
        enabledPrayers = try c.decodeIfPresent(Set<PrayerName>.self, forKey: .enabledPrayers) ?? [.fajr, .dhuhr, .maghrib]
        announcementNotifications = try c.decodeIfPresent(Bool.self, forKey: .announcementNotifications) ?? false
        timeSensitiveNotifications = try c.decodeIfPresent(Bool.self, forKey: .timeSensitiveNotifications) ?? true
        prayerSounds = try c.decodeIfPresent([String: PrayerAlertSound].self, forKey: .prayerSounds) ?? [:]
        let sourceID = try c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        selectedSourceID = CalendarSource.method(for: sourceID) == .system ? nil : sourceID
        // Absolute month-start overrides cannot be migrated to source-relative offsets.
        monthOffsets = try c.decodeIfPresent([MonthOffset].self, forKey: .monthOffsets) ?? []
        hiddenPrayers = try c.decodeIfPresent(Set<PrayerName>.self, forKey: .hiddenPrayers) ?? []
    }

    var isValid: Bool {
        (savedLocation == nil || savedLocation!.isValid)
            && (selectedSourceID == nil || CalendarSource.method(for: selectedSourceID) != .system)
            && monthOffsets.allSatisfy { $0.month.isValid && (-2 ... 2).contains($0.days) }
            && Set(monthOffsets.map(\.month)).count == monthOffsets.count
    }
}

@MainActor @Observable final class AppModel {
    private(set) var onboardingCompleted: Bool
    private(set) var onboardingStep: Int
    private(set) var preferences: Preferences
    private(set) var confirmations: [Announcement] = []
    var liveLocation: SavedLocation?
    var error: String?
    let content = ContentLibrary()
    let locationService = LocationService()
    let notifications = NotificationService()
    private let feedClient: FeedClient?
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var observer: NSObjectProtocol?
    private var notificationTask: Task<Void, Never>?
    private var calendarRevision = 0
    private let key = "preferences.v1"
    var location: SavedLocation? {
        liveLocation ?? preferences.savedLocation
    }

    var zone: TimeZone {
        location?.timeZone ?? .current
    }

    var engine: CalendarEngine {
        (try? CalendarEngine(timeZone: zone, offsets: preferences.monthOffsets, confirmed: confirmations.map(\.correction))) ?? (try! CalendarEngine(timeZone: zone))
    }

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default, feedClient: FeedClient? = nil) {
        self.defaults = defaults; self.cloud = cloud
        onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
        onboardingStep = min(4, max(0, defaults.integer(forKey: "onboardingStep")))
        self.feedClient = feedClient
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        preferences = decoded?.isValid == true ? decoded! : Preferences()
        liveLocation = defaults.data(forKey: "deviceLocation.v1")
            .flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        if let feed = feedClient?.cachedFeed(), let location,
           let matching = try? feed.matching(location: location, sourceID: preferences.selectedSourceID),
           (try? CalendarEngine(timeZone: zone, offsets: preferences.monthOffsets, confirmed: matching.map(\.correction))) != nil
        {
            confirmations = matching
        }
        if let cloud {
            observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.receiveCloud() }
            }
            cloud.synchronize()
            receiveCloud()
        }
    }

    func moveOnboarding(by offset: Int) {
        onboardingStep = min(4, max(0, onboardingStep + offset))
        defaults.set(onboardingStep, forKey: "onboardingStep")
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        guard location?.isValid == true else { return false }
        defaults.set(true, forKey: "onboardingCompleted")
        onboardingCompleted = true
        onboardingStep = 0
        defaults.removeObject(forKey: "onboardingStep")
        reschedule()
        return true
    }

    private func receiveCloud() {
        guard let data = cloud?.data(forKey: key), let incoming = try? JSONDecoder().decode(Preferences.self, from: data), incoming.isValid else { return }
        let matching = incoming.selectedSourceID == preferences.selectedSourceID ? confirmations : []
        guard (try? CalendarEngine(timeZone: (liveLocation ?? incoming.savedLocation)?.timeZone ?? .current,
                                   offsets: incoming.monthOffsets, confirmed: matching.map(\.correction))) != nil else { return }
        let sourceChanged = incoming.selectedSourceID != preferences.selectedSourceID
        calendarRevision += 1
        confirmations = matching; preferences = incoming
        if let normalized = try? JSONEncoder().encode(incoming) {
            defaults.set(normalized, forKey: key)
        }
        reschedule()
        if sourceChanged {
            refreshCalendar()
        }
    }

    @discardableResult
    func update(_ change: (inout Preferences) -> Void) -> Bool {
        var updated = preferences; change(&updated)
        guard updated.isValid, let data = try? JSONEncoder().encode(updated) else { error = String(localized: "Invalid preferences."); return false }
        let sourceChanged = updated.selectedSourceID != preferences.selectedSourceID
        let matching = sourceChanged ? [] : confirmations
        do {
            _ = try CalendarEngine(timeZone: (liveLocation ?? updated.savedLocation)?.timeZone ?? .current,
                                   offsets: updated.monthOffsets, confirmed: matching.map(\.correction))
        } catch { self.error = error.localizedDescription; return false }
        calendarRevision += 1
        confirmations = matching
        preferences = updated; defaults.set(data, forKey: key); cloud?.set(data, forKey: key)
        reschedule()
        if sourceChanged {
            refreshCalendar()
        }
        return true
    }

    func refreshCalendar() {
        Task { await refreshInBackground() }
    }

    func select(_ location: SavedLocation) {
        guard location.isValid else { return }
        let previous = liveLocation
        liveLocation = nil
        if update({ $0.savedLocation = location }) {
            defaults.removeObject(forKey: "deviceLocation.v1")
        } else {
            liveLocation = previous
        }
    }

    func applyLive(_ location: SavedLocation) {
        guard location.isValid, let data = try? JSONEncoder().encode(location) else { return }
        do { _ = try CalendarEngine(timeZone: location.timeZone, offsets: preferences.monthOffsets, confirmed: confirmations.map(\.correction)) }
        catch { self.error = error.localizedDescription; return }
        calendarRevision += 1
        liveLocation = location
        defaults.set(data, forKey: "deviceLocation.v1")
        reschedule()
    }

    func correct(month: HijriMonth, offset: Int) throws {
        let rows = preferences.monthOffsets.filter { $0.month != month }
            + (offset == 0 ? [] : [MonthOffset(month: month, days: offset)])
        _ = try CalendarEngine(timeZone: zone, offsets: rows, confirmed: confirmations.map(\.correction))
        update { $0.monthOffsets = rows }
    }

    func receive(_ feed: CorrectionsFeed) async throws {
        guard let location else { return }
        let matching = try feed.matching(location: location, sourceID: preferences.selectedSourceID)
        _ = try CalendarEngine(timeZone: zone, offsets: preferences.monthOffsets, confirmed: matching.map(\.correction))
        confirmations = matching
        syncWidgets()
        let currentMonth = engine.resolve(Date()).month
        let relevant = matching.filter { $0.month >= currentMonth && $0.month <= currentMonth.advanced(1) }
        await notifications.announce(relevant, enabled: preferences.announcementNotifications)
    }

    @discardableResult func refreshInBackground() async -> Bool {
        var succeeded = true
        let revision = calendarRevision
        if let feedClient, let requestedLocation = location, let requestedSource = preferences.selectedSourceID {
            do {
                let feed = try await feedClient.refresh()
                try Task.checkCancellation()
                // A response for an old location or source must not update the current calendar.
                guard calendarRevision == revision, location == requestedLocation, preferences.selectedSourceID == requestedSource else { return false }
                try await receive(feed)
            } catch {
                succeeded = false
            }
        }
        guard !Task.isCancelled else { return false }
        reschedule()
        let work = notificationTask
        await withTaskCancellationHandler {
            await work?.value
        } onCancel: {
            work?.cancel()
        }
        return succeeded && !Task.isCancelled
    }

    private func syncWidgets() {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let prayers = WidgetPrayerSettings(location: location, method: preferences.prayerMethod,
                                           hiddenPrayers: preferences.hiddenPrayers, imsakMinutes: preferences.imsakMinutes)
        let manual = engine.corrections.values.filter { $0.provenance == .manual }.sorted { $0.month < $1.month }
        let calendar = WidgetCalendarSettings(timeZoneID: location?.timeZoneID,
                                              showFeelsLikeTemperature: preferences.showFeelsLikeTemperature,
                                              manual: manual, confirmed: confirmations.map(\.correction))
        let prayersChanged = WidgetPrayerStore.write(prayers)
        let calendarChanged = calendar.write()
        WatchConnectivityService.shared.send(.init(prayers: prayers, calendar: calendar))
        if prayersChanged || calendarChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func reschedule() {
        syncWidgets()
        BackgroundRefresh.schedule()
        let previous = notificationTask
        previous?.cancel()
        let prefs = preferences, location = location
        notificationTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await notifications.rebuild(preferences: prefs, location: location)
        }
    }

    func setPrayer(_ prayer: PrayerName, enabled: Bool) async {
        if enabled, await !(notifications.authorize()) {
            error = String(localized: "Notifications are disabled. Enable them in system Settings."); return
        }
        update {
            if enabled {
                $0.enabledPrayers.insert(prayer)
            } else {
                $0.enabledPrayers.remove(prayer)
            }
        }
    }
}
