import Foundation
import Observation
import WidgetKit

struct Preferences: Codable, Equatable, Sendable {
    var savedLocation: SavedLocation?
    var prayerMethod: PrayerMethod = .jafari
    var imsakMinutes = 10
    var enabledPrayers: Set<PrayerName> = [.fajr, .dhuhr, .maghrib]
    var showFeelsLikeTemperature = false
    var announcementNotifications = false
    var selectedSourceID: String?
    var overrides: [MonthCorrection] = []
    var hiddenPrayers: Set<PrayerName> = []
    func isVisible(_ prayer: PrayerName) -> Bool {
        prayer.isVisible(hidden: hiddenPrayers)
    }

    enum CodingKeys: String, CodingKey {
        case showFeelsLikeTemperature, savedLocation, prayerMethod, imsakMinutes, enabledPrayers, announcementNotifications, selectedSourceID, overrides, hiddenPrayers
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
        selectedSourceID = try c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        overrides = try c.decodeIfPresent([MonthCorrection].self, forKey: .overrides) ?? []
        hiddenPrayers = try c.decodeIfPresent(Set<PrayerName>.self, forKey: .hiddenPrayers) ?? []
    }

    var isValid: Bool {
        (savedLocation == nil || savedLocation!.isValid) && overrides.allSatisfy { $0.provenance == .manual }
            && (try? CalendarEngine(timeZone: savedLocation?.timeZone ?? .gmt, manual: overrides)) != nil
    }
}

@MainActor @Observable final class AppModel {
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
    private let key = "preferences.v1"
    var location: SavedLocation? {
        liveLocation ?? preferences.savedLocation
    }

    var zone: TimeZone {
        location?.timeZone ?? .current
    }

    var engine: CalendarEngine {
        (try? CalendarEngine(timeZone: zone, manual: preferences.overrides, confirmed: confirmations.map(\.correction))) ?? (try! CalendarEngine(timeZone: zone))
    }

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default, feedClient: FeedClient? = nil) {
        self.defaults = defaults; self.cloud = cloud
        self.feedClient = feedClient
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        preferences = decoded?.isValid == true ? decoded! : Preferences()
        liveLocation = defaults.data(forKey: "deviceLocation.v1")
            .flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        if let cloud {
            observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.receiveCloud() }
            }
            cloud.synchronize()
            receiveCloud()
        }
    }

    private func receiveCloud() {
        guard let data = cloud?.data(forKey: key), let incoming = try? JSONDecoder().decode(Preferences.self, from: data), incoming.isValid else { return }
        confirmations = []; preferences = incoming; defaults.set(data, forKey: key); reschedule()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var updated = preferences; change(&updated)
        guard updated.isValid, let data = try? JSONEncoder().encode(updated) else { error = String(localized: "Invalid preferences."); return }
        if updated.selectedSourceID == preferences.selectedSourceID && updated.savedLocation == preferences.savedLocation {
            do { _ = try CalendarEngine(timeZone: zone, manual: updated.overrides, confirmed: confirmations.map(\.correction)) }
            catch { self.error = error.localizedDescription; return }
        }
        if updated.selectedSourceID != preferences.selectedSourceID || updated.savedLocation != preferences.savedLocation {
            confirmations = []
        }
        preferences = updated; defaults.set(data, forKey: key); cloud?.set(data, forKey: key)
        reschedule()
    }

    func select(_ location: SavedLocation) {
        guard location.isValid else { return }
        liveLocation = nil
        defaults.removeObject(forKey: "deviceLocation.v1")
        update { $0.savedLocation = location }
    }

    func applyLive(_ location: SavedLocation) {
        guard location.isValid, let data = try? JSONEncoder().encode(location) else { return }
        confirmations = []; liveLocation = location
        defaults.set(data, forKey: "deviceLocation.v1")
        reschedule()
    }

    func correct(month: HijriMonth, start: Date) throws {
        let row = MonthCorrection(month: month, start: CivilDate(start, in: zone), provenance: .manual, sourceID: nil)
        let rows = preferences.overrides.filter { $0.month != month } + [row]
        _ = try CalendarEngine(timeZone: zone, manual: rows, confirmed: confirmations.map(\.correction))
        update { $0.overrides = rows }
    }

    func reset(_ month: HijriMonth) {
        update { $0.overrides.removeAll { $0.month == month } }
    }

    func receive(_ feed: CorrectionsFeed) async throws {
        guard let location else { return }
        let matching = try feed.matching(location: location, sourceID: preferences.selectedSourceID)
        _ = try CalendarEngine(timeZone: zone, manual: preferences.overrides, confirmed: matching.map(\.correction))
        confirmations = matching
        syncWidgets()
        let currentMonth = engine.resolve(Date()).month
        let relevant = matching.filter { $0.month >= currentMonth && $0.month <= currentMonth.advanced(1) }
        await notifications.announce(relevant, enabled: preferences.announcementNotifications)
    }

    @discardableResult func refreshInBackground() async -> Bool {
        var succeeded = true
        if let feedClient, let requestedLocation = location, let requestedSource = preferences.selectedSourceID {
            do {
                let feed = try await feedClient.refresh()
                try Task.checkCancellation()
                // A response for an old location or source must not update the current calendar.
                guard location == requestedLocation, preferences.selectedSourceID == requestedSource else { return false }
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
        let calendar = WidgetCalendarSettings(timeZoneID: location?.timeZoneID,
                                              manual: preferences.overrides, confirmed: confirmations.map(\.correction))
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
