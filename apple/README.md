# Apple apps

Native iPhone/iPad app and Apple Watch companion using Swift 6 and SwiftUI. Requires iOS 26+ / watchOS 26+ and a compatible Xcode installation.

Open `Muntathir.xcodeproj`. Use `Muntathir` for iPhone/iPad, `MuntathirWatch` for Watch, and `MuntathirWidgets` for widget development. Select your signing team for device builds. Enable iCloud Key-Value Store for the iPhone app and `group.com.aljaroudi.Muntathir` for app/widget targets on both platforms.

## Commands

From repository root: `make apple-format`, `make apple-build`, and `make apple-test`. Build uses an unsigned iOS Simulator destination and includes embedded extensions. Tests select a compatible iPhone simulator; set `TEST_DESTINATION` to override it.

## Components

- [iPhone/iPad](Muntathir/): navigation, prayer counter, preferences, notifications, and daily ayah.
- [iOS/CarPlay widgets](MuntathirWidgets/).
- [Watch app](MuntathirWatch/) and [complications](MuntathirWatchWidgets/).
- [Shared calendar, feed contract, and content provenance](Shared/).
- [Unit/integration tests](MuntathirTests/) and [UI tests](MuntathirUITests/).

Core Swift sources live in `Muntathir/Core` and are reused directly by Apple targets. Adhan 1.5.0 is pinned in the Xcode project's package resolution file. There is no separate prayer engine. Shared fixtures are reference data; test copies are bundle resources.

`AppIcon.icon` is the shared Icon Composer source for iPhone/iPad and Watch in Debug and Release. Widget extensions use their containing app's identity. Quran Arabic text must never be edited. `QPCHafs.woff2` is registered through `UIAppFonts` with PostScript name `KFGQPCHAFSUthmanicScript-Regula`.

## Release checks

Validate real-device compass/calibration, notifications/background delivery, paired Watch synchronization and complications, CarPlay layouts, signed App Group provisioning, two-device iCloud sync, VoiceOver, and accessibility sizes. Validate proximity counting on notch and Dynamic Island iPhones, including placement, display recovery, timing, interruptions, and a four-rakaa session. Review event dates and Arabic titles editorially.

Production corrections endpoint/source catalog and push delivery remain unconfigured. Simulator tests cannot prove hardware behavior or deployed feed delivery.
