import CoreFoundation
import Foundation

protocol ReadingPreferencesCloud: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ReadingPreferencesCloud {}

/// Only user choices cross devices; caches, permissions and session state stay local.
@MainActor final class ReadingPreferencesSync {
    static let keys = ["readingSizePercent", "quranReadingMode", "hadithEnglishEnabled.v2",
                       "supplicationTranslation.v2", "savedGroupByDate", "highlightColorCount", "highlightColorOrder", QuranTranslationPreferences.selectionKey]
    private let defaults: UserDefaults
    private let translationDefaults: UserDefaults
    private let cloud: any ReadingPreferencesCloud
    private let selectTranslation: (String) -> Void
    private var previous: [String: NSObject] = [:]
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults, translationDefaults: UserDefaults, cloud: any ReadingPreferencesCloud,
         selectTranslation: @escaping (String) -> Void)
    {
        self.defaults = defaults
        self.translationDefaults = translationDefaults
        self.cloud = cloud
        self.selectTranslation = selectTranslation
        cloud.synchronize()
        receive(seedMissing: true)
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishChanges() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            Task { @MainActor [weak self] in self?.receive(keys: keys) }
        })
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func storage(for key: String) -> UserDefaults {
        key == QuranTranslationPreferences.selectionKey ? translationDefaults : defaults
    }

    static func valid(_ value: Any, for key: String) -> Bool {
        switch key {
        case "highlightColorCount":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return (1 ... 12).contains(number.intValue) && number.doubleValue == Double(number.intValue)
        case "highlightColorOrder":
            guard let order = value as? String else { return false }
            return HighlightPalette.validOrder(order)
        case "readingSizePercent":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return (80 ... 160).contains(number.intValue) && number.doubleValue == Double(number.intValue)
        case "hadithEnglishEnabled.v2", "savedGroupByDate":
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        case "quranReadingMode": return ["verses", "mushaf"].contains(value as? String ?? "")
        case "supplicationTranslation.v2":
            guard let value = value as? String else { return false }
            return ["auto", "none"].contains(value) || Locale.LanguageCode.isoLanguageCodes.contains { $0.identifier == value }
        case QuranTranslationPreferences.selectionKey:
            guard let value = value as? String else { return false }
            return value == "auto" || value.isEmpty || QuranTranslation.catalog.contains { $0.id == value }
        default: return false
        }
    }

    func receive(keys: [String]? = nil, seedMissing: Bool = false) {
        for key in Self.keys where keys?.contains(key) ?? true {
            let storage = storage(for: key)
            if let value = cloud.object(forKey: key), Self.valid(value, for: key) {
                // Update the snapshot before writing defaults to avoid echoing imports.
                previous[key] = value as? NSObject
                if key == QuranTranslationPreferences.selectionKey, let selection = value as? String {
                    selectTranslation(selection)
                }
                storage.set(value, forKey: key)
            } else if seedMissing, cloud.object(forKey: key) == nil,
                      let local = storage.object(forKey: key), Self.valid(local, for: key)
            {
                cloud.set(local, forKey: key)
            }
            if seedMissing {
                previous[key] = storage.object(forKey: key) as? NSObject
            }
        }
    }

    func publishChanges() {
        for key in Self.keys {
            guard let value = storage(for: key).object(forKey: key) as? NSObject,
                  value != previous[key], Self.valid(value, for: key) else { continue }
            previous[key] = value
            cloud.set(value, forKey: key)
        }
    }
}
