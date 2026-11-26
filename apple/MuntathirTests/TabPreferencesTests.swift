import Foundation
@testable import Muntathir
import Testing

struct TabPreferencesTests {
    @Test func defaultsAndExplicitEmptySelection() throws {
        #expect(Preferences().tabShortcuts == [.calendar])
        #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).tabShortcuts == [.calendar])
        #expect(try JSONDecoder().decode(Preferences.self, from: Data(#"{"tabShortcuts":[]}"#.utf8)).tabShortcuts.isEmpty)
    }

    @Test func unknownDuplicatesAndOverflowAreRemovedWithoutChangingOrder() throws {
        let data = Data(#"{"tabShortcuts":["future","events","events","today","hadith","quran","qibla","tools"]}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(preferences.tabShortcuts == [.events, .hadith, .quran])
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }

    @Test func selectedDestinationSurvivesReorderingButNotRemoval() {
        #expect(AppTab.tool(.hadith).available(in: [.quran, .hadith]) == .tool(.hadith))
        #expect(AppTab.tool(.hadith).available(in: [.quran]) == .today)
        #expect(AppTab.today.available(in: []) == .today)
        #expect(AppTab.tools.available(in: []) == .tools)
    }

    @Test func selectionSurvivesSidebarChanges() {
        #expect(AppTab.tool(.qibla).withoutSidebar(shortcuts: [.calendar]) == .tools)
        #expect(AppTab.tool(.calendar).withoutSidebar(shortcuts: [.calendar]) == .tool(.calendar))
        #expect(AppTab.settings.withoutSidebar(shortcuts: []) == .tools)
        #expect(AppTab.today.withoutSidebar(shortcuts: []) == .today)
        #expect(AppTab.tools.withSidebar(toolsRoot: .tool(.qibla)) == .tool(.qibla))
        #expect(AppTab.tools.withSidebar(toolsRoot: nil) == .today)
        #expect(AppTab.tools.withSidebar(toolsRoot: .browser) == .today)
        #expect(AppTab.tool(.hadith).withSidebar(toolsRoot: nil) == .tool(.hadith))
    }

    @MainActor @Test func localChangesAndIncomingCloudPreferencesPersist() throws {
        let suite = "TabPreferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        #expect(model.update { $0.tabShortcuts = [.hadith, .events, .quran, .qibla] })
        #expect(AppModel(defaults: defaults, cloud: nil).preferences.tabShortcuts == [.hadith, .events, .quran])
        var remote = model.preferences
        remote.tabShortcuts = [.quran, .events]
        try model.receiveSyncedPreferences(JSONEncoder().encode(remote))
        #expect(model.preferences.tabShortcuts == [.quran, .events])
        #expect(AppModel(defaults: defaults, cloud: nil).preferences.tabShortcuts == [.quran, .events])
        model.receiveSyncedPreferences(Data("broken".utf8))
        #expect(model.preferences == remote)
    }
}
