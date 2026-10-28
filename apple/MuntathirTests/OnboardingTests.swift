import Foundation
@testable import Muntathir
import Testing

struct OnboardingTests {
    @MainActor @Test func completionRequiresLocationAndSurvivesRelaunch() throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        #expect(model.onboardingCompleted == false)
        #expect(model.completeOnboarding() == false)
        #expect(defaults.bool(forKey: "onboardingCompleted") == false)
        #expect(model.preferences.prayerMethod == .tehran)
        #expect(model.preferences.enabledPrayers == [.fajr, .dhuhr, .maghrib])

        model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        model.update { $0.prayerMethod = .tehran }
        let interrupted = AppModel(defaults: defaults, cloud: nil)
        #expect(interrupted.onboardingCompleted == false)
        #expect(interrupted.location == model.location)
        #expect(interrupted.preferences.prayerMethod == .tehran)
        #expect(interrupted.completeOnboarding())
        #expect(AppModel(defaults: defaults, cloud: nil).onboardingCompleted)
        let encoded = try JSONEncoder().encode(interrupted.preferences)
        #expect(String(decoding: encoded, as: UTF8.self).contains("onboardingCompleted") == false)
    }

    @MainActor @Test func languageStepPersistsAcrossRelaunchAndCompletionClearsIt() throws {
        let suite = "OnboardingLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        model.moveOnboarding(by: 1)
        #expect(AppModel(defaults: defaults, cloud: nil).onboardingStep == 1)
        model.moveOnboarding(by: -10)
        #expect(model.onboardingStep == 0)
        model.moveOnboarding(by: 100)
        #expect(model.onboardingStep == 4)
        #expect(!model.completeOnboarding())
        #expect(model.onboardingStep == 4)
        model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        #expect(model.completeOnboarding())
        #expect(defaults.object(forKey: "onboardingStep") == nil)
        #expect(AppModel(defaults: defaults, cloud: nil).onboardingStep == 0)
    }

    @MainActor @Test func rememberedDeviceLocationDoesNotBypassOnboarding() throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        model.applyLive(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Device location", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        let restored = AppModel(defaults: defaults, cloud: nil)
        #expect(restored.liveLocation != nil)
        #expect(restored.onboardingCompleted == false)
        #expect(restored.completeOnboarding())
    }
}
