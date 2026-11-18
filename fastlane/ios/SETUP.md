# Manual Apple releases

Use the [shared Fastlane setup](../SETUP.md) on the signing Mac. Run lane commands from the repository root.

## Release commands

```sh
just lane ios testflight_public
just lane ios app_store
```

- **TestFlight Public** runs the unit/UI regression suite on the newest compatible installed iPhone simulator and submits the build to the external `Public` group with localized What to Test. TestFlight invitations pull screenshots from the latest App Store version ready for distribution. Screenshot capture and upload run in the App Store lane. [Apple’s TestFlight screenshot rules](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- **App Store** runs the suite on that iPhone and the configured iPad Pro. It uploads fresh screenshots and listing metadata, syncs Asset Packs, uploads composed header/search creatives to the App Asset Library, and submits the existing `testflight_public` build for automatic publication after approval (without uploading a new binary). Keep existing preview videos intact.
- Both commands are local and manual. The GitHub Actions deployment workflow is removed. Wait for one release to finish before starting another checkout or uploading the same version elsewhere. A checkout lock prevents overlapping release commands in the same working directory.

The workflow deletion takes effect on GitHub once it reaches the default branch. Until then, disable the old **Local Apple deployment** workflow in Actions before opening or merging a PR that would trigger it.

## Before running

1. Set the shared marketing version with `just version X.Y.Z` and, for the App Store lane, manually create the matching editable iOS draft in App Store Connect. Keep the project build number at `1`. Xcode assigns the final build number during upload. [Apple’s build-number rules](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
2. Update `fastlane/ios/beta_notes/<locale>.txt` for What to Test or `fastlane/ios/metadata/<locale>/release_notes.txt` for What’s New. Each lane compares its notes against the latest Public build or live App Store version. All 14 store locales must pass validation and at least one note must differ when Apple has prior notes. Use `force:true` on the release command to allow intentionally unchanged notes. The draft, tests, archive, screenshots, and metadata validity checks still run. App Store Connect rejects modifier letters such as `ʿ` in What’s New — `check` fails those before upload. After a successful local screenshot refresh, `app_store skip_screenshots:true` reuses `apple/build/marketing/store` and `apple/build/marketing/creative` instead of re-capturing (~2h).
3. Configure the App Store Connect key in `~/.config/muntathir/fastlane.env` using `fastlane/.env.local.example`. Set `MUNTATHIR_REVIEW_CONFIG` to a private JSON file for export compliance and any missing review fields. See `fastlane/ios/review.example.json`. Protect the credentials and review files with `chmod 600`. Automatic signing covers the app, Watch companion, and extensions. Set up the external group named `Public` and enable its public link in App Store Connect if needed.
4. Install Apple Transporter for asset uploads. For the App Store lane, also install the capture simulators and runtimes below, a shutdown Apple Watch Series 12 (46mm) simulator, ImageMagick, and FFmpeg. Generate the local content databases and validate the assets with `python3 apple/AssetPacks/assets.py validate --content all`.

Both release lanes compare the manifest and payload files with each cached archive under `apple/build/AssetPacks/archives/`. They rebuild changed packs, update the bundled download-size estimates when repackaging, and reuse an Apple version whenever its checksum matches the archive. Keep the originally uploaded archives on the release Mac. A missing archive, or an older remote version without a comparable checksum, can require a one-time upload to establish the match. The App Store lane attaches the exact processed versions that differ from the live packs. After submitting a Public build, submit the listed pack versions for external testing in App Store Connect. [Apple’s asset-pack testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs)

Manage localized names, descriptions, keywords, promotional text, support/privacy URLs, and copyright under `fastlane/ios/metadata/`. Persian interface copy is supported and its store copy stays under `fastlane/ios/listing-drafts/fa/`. Keep private review contacts in App Store Connect or the private review JSON.

## Local commands

- `check` validates localization, metadata, screenshot configuration, and lane behavior offline.
- `tests` runs the local unit/UI regressions on one iPhone. Both release lanes run screenshot capture separately.
- `screenshots`, `watch_screenshots`, and `style` capture and compose the iOS screens and Watch prayer screen in all 15 app locales. The App Store upload selects the locales supported by App Store Connect. Use `just lane ios screenshots languages:ar,en,fa` and `just lane ios style languages:ar,en,fa`. Canonical locale IDs remain supported. Screenshot workers default to 2 (override with `workers:N`, max 8); they share one simulator lock.
- `previews` generates optional videos. `previews devices:"iPhone Duo"` generates Duo videos for manual upload.
- `marketing` refreshes screenshots and generates the standard previews locally.

## Capture settings and outputs

Captures use a clean isolated test preferences suite, Mecca, 23 October 2026, light appearance and local weather data. Fajr, Dhuhr and Maghrib are visible, with sunset enabled; all other optional times are hidden. This fixture is Debug-only and leaves normal app preferences unchanged. Quran source text is never modified. Screenshot captures read 94:6 from the bundled Quran database. Video captures and SwiftUI previews retain `exampleAyah` from `DailyAyahCard.swift`; each reference matches its text.

Screenshot captures use ayah 94:6 (index 6096). Quran capture builds stage downloaded translations locally, with English where no capture translation matches and Arabic alone in Arabic. Release bundles only Arabic and English. The capture runner stages the production Hadith database in its Debug bundle under the marketing launch flag; Release uses the hosted Hadith pack.

Standard devices use `SCREENSHOT_IOS_VERSION` (default 27.0), with iPhone and iPad captured concurrently for each locale. Locale workers use separate DerivedData clones, logs and raw directories, but serialize simulator access because Snapshot selects the same device UUIDs across workers. Duo uses `SCREENSHOT_DUO_IOS_VERSION` (default 27.2) after standard devices within each worker. Install the runtimes in Xcode. Current snapshot captures use the native 1398 × 2034 Duo output; validation also accepts 2007 × 2853 and both landscape equivalents. Duo video recording explicitly selects the outer `primary` display; the simulator default can target the blank inner display. QA rejects blank frames. Capturing a single display does not establish layout correctness across folding transitions.

Edit [the screenshot config](marketing/screenshots.json) to set the ordered screen IDs, headlines for each locale, brand text, two RGB gradient stops, and the creative canvas size. Numbered screen IDs control upload order and match the snapshot names in `MarketingScreenshotTests`. The Watch slot captures the native app. Frameit provides the iPhone 17 Pro Max, iPad and Duo bezels. The iPad capture fits the available 12.9-inch bezel without stretching and exports on the accepted 13-inch canvas. ImageMagick is required (`brew install imagemagick`). AppKit draws localized text, and final images are flattened with no alpha channel.

`style` also builds one locale-agnostic universal creative at **5244 × 2950** (PNG, no alpha) from the app icon: emerald gradient `#174F45 → #082F2B`, a quiet tiled hourglass–dome mark, and one clear mark in Apple’s safe area (paths match `AppIcon.icon/Assets/Muntathir-Icon.svg`). `style` copies the same PNG into each locale folder for upload. Follow [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/): one clear idea, no pricing/URLs/awards, and 4+ safe imagery. The `app_store` lane uploads each creative to the App Asset Library (`CREATIVE_ASSETS`) and places the same image as `PRODUCT_PAGE_HEADER_ASSET` and `APP_STORE_SEARCH_RESULTS_ASSET` on the draft localization (preferring the `DEFAULT_PROFILE` placement group from Apple’s reference data).

The Debug capture clock advances the actual Today UI continuously from sunrise to sunset. `ffmpeg` exports H.264/yuv420p video at 30 fps, with silent stereo AAC audio. `ffprobe` checks format and duration. Release builds exclude the capture controls.

Generated files live under ignored `apple/build/marketing/` (from the repo root):

- `raw/<locale>/`: original simulator PNGs from `screenshots` / `just lane ios screenshots`. Each run deletes that locale’s prior raw (and `frames/`) files before writing.
- `store/<locale>/`: framed App Store PNGs from `style` / `just lane ios style` (Watch slot kept if present). Device shots for the styled locales are replaced each run.
- `creative/universal.png` and `creative/<locale>/universal.png`: 5244 × 2950 brand creative from `style` (uploaded by `app_store`).
- `frames/`: intermediate bezel images (disposable).
- `watch/`: native Watch captures required for the embedded companion.
- `previews/`: 15-second standard iPhone/iPad videos and start/middle/end QA frames.
- `duo-previews/`: 15-second Duo videos at 886 × 1920, with QA frames. Duo keeps the native screen proportions inside a neutral frame and background on Apple’s required 886 × 1920 canvas.

**Duo preview upload limitation:** Fastlane 2.241.2 supports Duo screenshots but has no Duo preview upload type. Optional Duo videos are exported separately with `just lane ios previews devices:"iPhone Duo"` for manual App Store Connect upload. Keeping them outside automatic preview discovery prevents silent skipping or assignment to another device slot. No undocumented preview enum is invented here; screenshots remain on classic Deliver while header/search creatives use the Asset Library client in `creative_assets.rb`.

For visual QA, run the local media lanes and inspect headline readability, Arabic joining and direction, the four prayer rows, and the Sun movement in previews. Simulator captures do not establish hardware compass, notifications or Watch behavior.

## Upload recovery and artifacts

Binary upload, Apple processing, and review submission are separate stages. If upload or processing errors, inspect **Build Uploads** in App Store Connect before retrying. Processing waits up to 30 minutes. If the expected build processed and a later step failed, finish its draft or Public distribution in App Store Connect using the exact version and build number printed by the lane. Rerunning a release command creates a new build. Screenshot replacement may need to be completed in App Store Connect if an upload stops partway through.

Failed uploads and processing retain the archive under `apple/build/`. Successful processing saves dSYMs under `apple/build/symbols/<version>-<build>/` and removes that archive. Test and capture failures retain local diagnostics. `just lane ios cleanup` removes project-local disposable caches after the run.
