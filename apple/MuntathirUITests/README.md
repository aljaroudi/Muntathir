# UI tests

Run the `Muntathir` scheme tests in Xcode on an iOS 26+ simulator, or from repository root:

```sh
xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  -only-testing:MuntathirUITests
```

XCTest covers English/Arabic Tools navigation, Qibla tool availability, unavailable compass guidance, manual correction, and daily ayah sharing. Run on iPhone and iPad when changing layouts. UI tests remain manual and are not part of the pre-push hook.

Onboarding tests cover the app-language Settings link, resuming the same step after relaunch, required location, Back navigation, optional notifications, persisted completion, and Arabic accessibility layouts. Existing `--ui-testing` launches bypass onboarding. Add `--ui-testing-onboarding` to exercise it, `--ui-testing-mecca` to seed a deterministic location, and `--ui-testing-preserve-state` on relaunch to retain the test defaults. Run `OnboardingUITests` on both iPhone and iPad. Check real permission prompts, denied location with city-search fallback, offline search/retry, and notification delivery separately on a device.
