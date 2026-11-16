# Architecture

## Stack

Kotlin 2.x · AGP 9 · Compose BOM + Material 3 Expressive (dynamic color, emerald fallback) · Navigation 3 · Hilt · Coroutines/Flow · kotlinx.serialization · Room · DataStore · WorkManager · Glance · CameraX · Play Asset Delivery (`asset-delivery-ktx`) · Ktor client · Adhan Swift 1.5.0 ported into `core/prayer/adhan`.

minSdk 26, compile/target latest. Edge-to-edge, predictive back, per-app language (AppCompat `setApplicationLocales` + `locales_config.xml`). No AGSL; the Today sky uses an animated gradient `Brush`.

## Modules

```
android/
  core/    Pure Kotlin/JVM. Calendar, feed, prayer, solar/moon, qibla, text, tasbih, rakaat detector, models.
  app/     All Android code: ui/<feature>, data, assets, notifications, widgets.
  packs/   PAD modules: hadith, supplications, quran_translations, rulings.
```

## UI

- `NavigationSuiteScaffold` (bar on phones, rail on large screens) with Today, ≤3 user shortcuts, and Tools. Same rules as `AppTool.swift`.
- Nav3: one saved back stack per tab. List-detail scenes for Quran, Hadith, Rulings, Figures, Saved, Settings.
- Each screen: a ViewModel exposing one `StateFlow<UiState>` plus event functions. Composables stay stateless.
- RTL, `sp` text scaling, TalkBack labels. iOS accessibility IDs are reused as test tags.

## Data

| Kind | Store |
|---|---|
| Quran Arabic + English, events, surahs, daily ids | `assets/`, copied once to `noBackupFilesDir` |
| Hadith, Supplications, Rulings, Quran translations | PAD packs |
| Content SQLite (read-only, FTS5 + trigram) | `androidx.sqlite` **BundledSQLiteDriver** (platform SQLite lacks FTS5) |
| Preferences (`preferences.v1`, same JSON shape and validation as `Preferences.swift`) | DataStore |
| Device-local: onboarding step, live location, installation ID, hadith session | DataStore file excluded from backup |
| Highlights, bookmarks, prayer history, activity | Room (bundled driver) |

Schema checks match iOS: Hadith `application_id` 1230262606, `user_version` 7–8; Rulings 1179809601 v1. Keep the iOS record design (stable IDs, `modifiedAt`, tombstones) so that restore and merge logic stays identical.

## Backup (replaces iCloud)

`dataExtractionRules` (API 31+) and `fullBackupContent` (≤30):
- Include the Room DB and the preferences DataStore.
- Exclude the device-local DataStore, `noBackupFilesDir`, and PAD content.

## Asset packs

| Pack | Mode | Notes |
|---|---|---|
| `hadith` | on-demand | |
| `supplications` | fast-follow | Real file path; iOS "essential" equivalent |
| `quran_translations` | on-demand | Copy validated DBs to `noBackupFilesDir`, then `removePack` (iOS App Group flow) |
| `rulings` | on-demand | |

One `AssetPackBackend` interface over `AssetPackManager`, mirroring `AssetPackBackend.swift` events. Handle the confirmation dialogs (cellular / user confirmation) and the post-update "patching" state. Pack content ships with app releases. Packaging extends `apple/AssetPacks/assets.py` with an Android target that reuses the same validators.

## System

- **Notifications:** exact alarms (inexact fallback if not granted) → receiver posts the notification. Reschedule on boot, time/zone/locale change, app start, and preference change. One channel per category; channel IDs are versioned by sound (channel sounds are immutable). Full adhan via a short `mediaPlayback` foreground service.
- **Feed:** WorkManager periodic 12 h with a network constraint, same entry point as launch refresh. ETag + last-good cache. Store the host in punycode.
- **Widgets:** Glance in `app`, reading DataStore/Room directly.

## Testing

- `core`: JUnit ports of `apple/MuntathirTests` logic tests.
- Shared fixtures move to `shared/fixtures/` for both platforms.
- `app`: Compose UI tests (Hilt test modules, no launch-flag branches in production code) and Compose Preview screenshot tests (phone/foldable/tablet × ar/en × light/dark).
- `just android-build`, `just android-test`.
