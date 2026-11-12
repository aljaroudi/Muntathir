import Foundation
@testable import Muntathir
import SwiftData
import Testing

private final class MemoryReadingCloud: ReadingPreferencesCloud {
    var values: [String: Any] = [:]
    var writes: [String] = []
    func object(forKey key: String) -> Any? {
        values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value; writes.append(key)
    }

    func synchronize() -> Bool {
        true
    }
}

@MainActor struct ReadingPreferencesSyncTests {
    @Test func migratesImportsAndPublishesOnlyChangedPreferences() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let translations = try #require(UserDefaults(suiteName: name + ".translations"))
        defer {
            defaults.removePersistentDomain(forName: name)
            translations.removePersistentDomain(forName: name + ".translations")
        }
        defaults.set(120, forKey: "readingSizePercent")
        defaults.set("mushaf", forKey: "quranReadingMode")
        defaults.set(true, forKey: "onboardingCompleted")
        let cloud = MemoryReadingCloud()
        cloud.values["quranReadingMode"] = "verses"
        cloud.values[QuranTranslationPreferences.selectionKey] = "auto"
        var selected: String?
        let sync = ReadingPreferencesSync(defaults: defaults, translationDefaults: translations, cloud: cloud) { selected = $0 }
        #expect(cloud.writes == ["readingSizePercent"])
        #expect(defaults.string(forKey: "quranReadingMode") == "verses")
        #expect(selected == "auto")
        #expect(translations.string(forKey: QuranTranslationPreferences.selectionKey) == "auto")
        cloud.writes = []
        sync.publishChanges()
        #expect(cloud.writes.isEmpty)
        let order = HighlightColor.allCases.reversed().map(\.rawValue).joined(separator: ",")
        cloud.values["highlightColorOrder"] = order
        cloud.values["highlightColorCount"] = 8
        sync.receive(keys: ["highlightColorOrder", "highlightColorCount"])
        #expect(defaults.string(forKey: "highlightColorOrder") == order)
        #expect(defaults.integer(forKey: "highlightColorCount") == 8)
        sync.publishChanges()
        #expect(cloud.writes.isEmpty)
        defaults.set(140, forKey: "readingSizePercent")
        cloud.values["savedGroupByDate"] = true
        sync.receive(keys: ["savedGroupByDate"])
        sync.publishChanges()
        #expect(cloud.writes == ["readingSizePercent"])
        #expect(cloud.values["readingSizePercent"] as? Int == 140)
        #expect(defaults.bool(forKey: "savedGroupByDate"))
        cloud.values["readingSizePercent"] = 999
        sync.receive(keys: ["readingSizePercent"])
        #expect(defaults.integer(forKey: "readingSizePercent") == 140)
    }

    @Test func notificationsDeliverLocalAndRemoteChangesWithoutEcho() async throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryReadingCloud()
        let sync = ReadingPreferencesSync(defaults: defaults, translationDefaults: defaults, cloud: cloud) { _ in }
        defaults.set(130, forKey: "readingSizePercent")
        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: .seconds(3))
        while cloud.values["readingSizePercent"] == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cloud.values["readingSizePercent"] as? Int == 130)
        cloud.writes = []
        cloud.values["readingSizePercent"] = 150
        NotificationCenter.default.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud,
                                        userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: ["readingSizePercent"]])
        deadline = clock.now.advanced(by: .seconds(3))
        while defaults.integer(forKey: "readingSizePercent") != 150, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(defaults.integer(forKey: "readingSizePercent") == 150)
        sync.publishChanges()
        #expect(cloud.writes.isEmpty)
    }

    @Test func validatesIncomingChoices() {
        #expect(!ReadingPreferencesSync.valid(true, for: "readingSizePercent"))
        #expect(!ReadingPreferencesSync.valid(100.5, for: "readingSizePercent"))
        #expect(!ReadingPreferencesSync.valid("true", for: "hadithEnglishEnabled"))
        #expect(ReadingPreferencesSync.valid(false, for: "hadithEnglishEnabled"))
        #expect(!ReadingPreferencesSync.valid("bad", for: "quranReadingMode"))
        #expect(ReadingPreferencesSync.valid("en", for: "supplicationTranslation"))
        #expect(!ReadingPreferencesSync.valid("bad-language", for: "supplicationTranslation"))
        #expect(!ReadingPreferencesSync.valid("unknown", for: QuranTranslationPreferences.selectionKey))
    }

    @Test func allTwelveColorsRoundTripWithoutChangingLegacyValues() throws {
        #expect(HighlightColor.allCases.count == 12)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let store = QuranUserStore(configuration: configuration, installationID: "colors")
        for color in HighlightColor.allCases {
            let highlight = ReadingHighlight(source: "1:1", isHadith: false, excerpt: "text", reference: "1:1", color: color)
            #expect(try JSONDecoder().decode(ReadingHighlight.self, from: JSONEncoder().encode(highlight)) == highlight)
            try store.save(highlight)
        }
        #expect(Set(store.highlights.map(\.color)) == Set(HighlightColor.allCases))
        for raw in ["yellow", "green", "blue", "pink", "purple"] {
            #expect(try JSONDecoder().decode(HighlightColor.self, from: Data("\"\(raw)\"".utf8)).rawValue == raw)
        }
    }
}

extension ReadingPreferencesSyncTests {
    @Test func paletteDefaultsOrderingAndSyncValidation() {
        #expect(HighlightPalette.colors(order: HighlightPalette.defaultOrder, count: HighlightPalette.defaultCount) == [.yellow, .green, .blue, .pink, .purple, .orange])
        let reversed = HighlightColor.allCases.reversed().map(\.rawValue).joined(separator: ",")
        #expect(HighlightPalette.colors(order: reversed, count: 2) == [.brown, .indigo])
        #expect(ReadingPreferencesSync.valid(reversed, for: "highlightColorOrder"))
        #expect(!ReadingPreferencesSync.valid("yellow,yellow", for: "highlightColorOrder"))
        #expect(!ReadingPreferencesSync.valid(0, for: "highlightColorCount"))
        #expect(!ReadingPreferencesSync.valid(13, for: "highlightColorCount"))
        #expect(ReadingPreferencesSync.valid(12, for: "highlightColorCount"))
        #expect(HighlightPalette.colors(order: "bad", count: 6).count == 6)
    }
}
