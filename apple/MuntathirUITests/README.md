# UI tests

Run the `Muntathir` scheme tests in Xcode on an iOS 26+ simulator, or from repository root:

```sh
xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  -only-testing:MuntathirUITests
```

XCTest covers English/Arabic Tools navigation, Qibla tool availability, precise-location gating and the Qibla map without heading, manual correction, and daily ayah sharing. Run on iPhone and iPad when changing layouts. UI tests remain manual and are not part of the pre-push hook.

Onboarding tests cover the app-language Settings link, resuming the same step after relaunch, required location, Back navigation, optional notifications, persisted completion, and Arabic accessibility layouts. Existing `--ui-testing` launches bypass onboarding. Add `--ui-testing-onboarding` to exercise it, `--ui-testing-mecca` to seed a deterministic location, and `--ui-testing-preserve-state` on relaunch to retain the test defaults. Run `OnboardingUITests` on both iPhone and iPad. Check real permission prompts, denied location with city-search fallback, offline search/retry, and notification delivery separately on a device.

Hadith personal-data tests use `--ui-testing-hadith-fixture` together with `--ui-testing`. This Debug-only fixture creates an isolated local library so favorites, notes, image sharing, Arabic accessibility layout, and relaunch/scroll restoration can run without a hosted download. Keep the existing real-library tests for asset delivery and corpus browsing. The sharing test exercises the native Save Image action; permissions remain simulator/device-local.

Saved UI tests cover bookmark toggling, search, source/date grouping, persistence, and failure alerts. `--ui-testing-supplications-fixture` uses the isolated Debug library for supplication bookmark coverage without a hosted download.
The `--ui-testing-legacy-highlights` fixture seeds two whole-verse highlights to verify that existing overlapping highlights remain readable and editable. New highlight creation tests use native text selection.
