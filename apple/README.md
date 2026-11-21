# Apple apps

iPhone/iPad app and Apple Watch companion in Swift 6 and SwiftUI. Requires iOS 26+ / watchOS 26+.

## Setup

Open `Muntathir.xcodeproj`. Schemes: `Muntathir` (iPhone/iPad), `MuntathirWatch` (Watch), `MuntathirWidgets` (widgets). For device builds, select your signing team and enable:

- iCloud Key-Value Store for the iPhone app.
- App Group `group.com.aljaroudi.Muntathir` for every app and widget target.

From the repository root: `just apple-format`, `just apple-build` (unsigned simulator build), `just apple-test` (set `TEST_DESTINATION` to pick a simulator).

## Components

- [iPhone/iPad](Muntathir/)
- [iOS/CarPlay widgets](MuntathirWidgets/)
- [Watch app](MuntathirWatch/) and [complications](MuntathirWatchWidgets/)
- [Calendar, corrections feed, and content provenance](Shared/)
- [Asset packs](AssetPacks/) (Quran translations, Hadith, Supplications, Rulings)
- [Unit/integration tests](MuntathirTests/) and [UI tests](MuntathirUITests/)
- [Manual releases with Fastlane](../fastlane/ios/SETUP.md)

Core sources live in `Muntathir/Core` and are shared by all Apple targets. Prayer times come from Adhan 1.5.0, pinned in the package resolution file.

## Rules

- Never edit Quran Arabic text.
- `AppIcon.icon` (Icon Composer) is the single icon source for iPhone/iPad and Watch.
- Fonts: `QPCHafs.woff2` for Quran (registered through `UIAppFonts`, PostScript name `KFGQPCHAFSUthmanicScript-Regula`) and the bundled `Lateef-Light.ttf` for Arabic Hadith.
- Apple Weather marks in `Muntathir/Resources/WeatherAttribution.xcassets` are Apple's original `logoLight@3x` / `logoDark@3x` PNGs from `https://weatherkit.apple.com/attribution/{language}`. Keep the original artwork and filenames. Persian and Urdu use the English marks; Chinese uses `zh-CN` / `zh-TW`.

## Hadith data

Put the extracted hadith `app/data` contents in `temp/hadith-data/`, then run:

```sh
uv run build/hadith/build.py --sittah --four
```

The database ships as an on-demand asset pack, never bundled (see [asset packs](AssetPacks/)). Generated databases and source corpora are ignored by Git. Rebuild after changing the schema or any of these curated files in `build/hadith/data/`:

- `books-and-authors.json`: Arabic book and author names.
- `kafi-chapters.json`, `tahdhib-chapters.json`, `faqih-chapters.json`: attested Arabic section headings. The importer only fills missing names when the English title and narration boundaries still match.

Notes:

- Gradings are stored only for the Six Books, in `hadith_grading`. The importer does not assign broad authenticity categories.
- Al-Kafi omits the author's introduction. العتق، الحدود، and الديات are restored from the Dar al-Kutub edition because the Thaqalayn files lack them.
- Root/lemma search is off unless the builder gets `--experimental-morphology`. Rijal is not built.
- An installed asset keeps its old copy until a new pack replaces it.

## Release checks

Simulator tests can't prove hardware behavior, so check these on a device:

- Compass and calibration, notifications and background delivery, CarPlay layouts.
- Paired Watch sync and complications, signed App Group provisioning.
- iCloud sync across two devices, VoiceOver, accessibility text sizes.
- Event dates and Arabic titles (editorial review).

Before releasing Progress:

1. Deploy the `PrayerHistoryRecord` and `ProgressActivityRecord` schemas to production in `iCloud.com.aljaroudi.Muntathir`.
2. On two devices with the same iCloud account, record a prayer, a reading session, and a partial tasbih while offline. Reconnect and confirm the totals arrive without duplicates.
3. Confirm reading timers pause in the background and after five idle minutes.
