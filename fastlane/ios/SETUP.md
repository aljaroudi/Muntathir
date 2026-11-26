# Apple releases

Releases run locally on the signing Mac, from the repository root, after the [shared Fastlane setup](../SETUP.md). Wait for one release to finish before starting another or uploading the same version elsewhere; a checkout lock blocks overlapping runs in one working directory.

## Lanes

- **`beta`** runs unit tests on the newest installed compatible iPhone simulator and submits to the external `Public` TestFlight group with localized What to Test. TestFlight invitations show screenshots from the latest App Store version ready for distribution ([Apple's rules](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)).
- **`release`** ships iOS and Mac together. It runs the full unit and UI suite on that iPhone and the configured iPad Pro, refreshes the iOS, Watch and Mac screenshots, and syncs Asset Packs for both platforms. It then:
  - archives and uploads the Mac build, which skips TestFlight;
  - uploads both listings and the header/search creatives;
  - submits the existing iOS TestFlight build and the new Mac build for automatic release after approval.

  Existing preview videos are kept. Pass `mac:false` for an iOS-only release.
- **`check`** validates localization, metadata, screenshot config and lane behavior offline.
- **`tests`** runs the unit/UI regressions on one iPhone.
- **`screenshots`**, **`watch_screenshots`**, **`style`** capture and compose iOS and Watch screens in all 15 locales (the upload picks the locales App Store Connect supports). `languages:ar,en,fa` limits locales; `workers:N` (default 2, max 8) sets screenshot workers.
- **`mac_screenshots`** and **`mac_style`** capture the Mac app's window in each locale and compose it at 2880 × 1800. The Mac gallery has six screens: Today, Quran, Hadith, Supplications, Tasbih and Calendar. Qibla and Rakaat aren't on Mac.
- **`previews`** makes optional videos; `previews devices:"iPhone Duo"` makes Duo videos for manual upload.
- **`marketing`** refreshes iOS, Watch and Mac screenshots and standard previews.
- **`web_media`** exports the website's phone-tour media (see [web/README.md](../../web/README.md)).
- **`cleanup`** removes project-local disposable caches.

Options: `force:true` allows intentionally unchanged notes (all other checks still run). `release skip_screenshots:true` reuses `apple/build/marketing/store`, `mac/store` and `creative` from a successful local refresh instead of recapturing (~2 h).

## Before running

1. `just version X.Y.Z`. For `release`, create the matching editable iOS and macOS drafts in App Store Connect, both set to release automatically after approval. Keep the project build number at `1`; Xcode assigns it on upload ([Apple's rules](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)).
2. Update `fastlane/ios/beta_notes/<locale>.txt` (What to Test) or `shared/release-notes/changelog.json` (What's New; also bundled in the apps and rendered by `just changelog`). Add an entry per marketing version listing its shipping platforms (`ios`, `macos`). All 14 store locales must validate, and at least one note must differ from Apple's previous notes. App Store Connect rejects modifier letters such as `ʿ` in What's New; `check` catches them.
3. Put the App Store Connect key in `~/.config/muntathir/fastlane.env` (template: `fastlane/.env.local.example`; override the path with `MUNTATHIR_FASTLANE_ENV_FILE`). Set `MUNTATHIR_REVIEW_CONFIG` to a private JSON for export compliance and review fields (see `fastlane/ios/review.example.json`). `chmod 600` both files. Automatic signing covers the app, Watch companion and extensions. The external group must be named `Public`, with its public link enabled.
4. Install Apple Transporter. For `release`, also install the capture simulators and runtimes, a shut-down Apple Watch Series 12 (46mm) simulator, ImageMagick and FFmpeg. Build the content databases and run `just packs-check`.

## Asset packs

Both release lanes compare each pack's manifest and payload with the cached archive in `apple/build/AssetPacks/archives/`, rebuild changed packs (updating bundled download-size estimates), and reuse an Apple version whose checksum matches. Keep the uploaded archives on the release Mac; a missing archive or an old remote version without a comparable checksum can force a one-time upload. `release` attaches the processed versions that differ from the live packs. After submitting a Public build, submit the listed pack versions for external testing in App Store Connect ([Apple's instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs)).

## Metadata

Localized names, descriptions, keywords, promotional text, URLs and copyright live in `fastlane/ios/metadata/`. Persian store copy is in `fastlane/ios/listing-drafts/fa/`. Keep private review contacts in App Store Connect or the review JSON.

## Captures

- **Fixture (Debug only):** isolated preferences, Mecca, 23 October 2026, light mode, local weather data; Fajr, Dhuhr, Maghrib and sunset visible. Screenshots read ayah 94:6 (index 6096) from the bundled Quran database; videos and SwiftUI previews use `exampleAyah` in `DailyAyahCard.swift`. Quran capture builds stage downloaded translations (English where none matches, Arabic alone in Arabic); the Debug bundle stages the production Hadith database. Release builds exclude capture controls and bundle only Arabic and English.
- **Runtimes:** standard devices use `SCREENSHOT_IOS_VERSION` (default 27.2), iPhone and iPad concurrently per locale. Duo uses `SCREENSHOT_DUO_IOS_VERSION` (default 27.2). Workers use separate DerivedData clones but share one simulator lock, since Snapshot picks the same device UUIDs.
- **Duo:** native 1398 × 2034 output (validation also accepts 2007 × 2853 and landscape). Video records the outer `primary` display, since the default can target the blank inner one; QA rejects blank frames. One display doesn't prove folding-transition layout.
- **Config:** [marketing/screenshots.json](marketing/screenshots.json) sets ordered screen IDs (they set upload order and match `MarketingScreenshotTests` names), per-locale headlines, brand text, gradient stops and creative canvas. Phone captures run on iPhone 18 Pro Max; Frameit supplies iPhone 17 Pro Max (6.9-inch), iPad and Duo bezels, and the iPad shot fits the 12.9-inch bezel on the 13-inch canvas. Images are flattened without alpha.
- **Creative:** `style` builds one 5244 × 2950 PNG from the app icon (emerald `#174F45 → #082F2B`, paths from `AppIcon.icon/Assets/Muntathir-Icon.svg`) and copies it per locale. `release` uploads it to the App Asset Library and sets it as `PRODUCT_PAGE_HEADER_ASSET` and `APP_STORE_SEARCH_RESULTS_ASSET` (`creative_assets.rb`). Follow [Apple's asset best practices](https://developer.apple.com/app-store/asset-best-practices/): no pricing, URLs or awards.
- **Video:** the Debug clock runs Today from sunrise to sunset; `ffmpeg` exports H.264/yuv420p 30 fps with silent stereo AAC, checked by `ffprobe`.
- **Duo previews:** Fastlane 2.241.2 has no Duo preview upload type, so Duo videos are exported separately for manual upload and kept out of automatic preview discovery.
- **QA:** check headline readability, Arabic joining and direction, the four prayer rows, and Sun movement. Simulators don't cover compass, notifications or Watch hardware.

Outputs (git-ignored, under `apple/build/marketing/`):

- `raw/<locale>/`: simulator PNGs (each run clears the locale's `raw` and `frames`).
- `store/<locale>/`: framed App Store PNGs (Watch slot kept if present).
- `creative/universal.png`, `creative/<locale>/universal.png`: brand creative.
- `frames/`: intermediate bezels (disposable). `watch/`: native Watch captures.
- `previews/`: 15 s iPhone/iPad videos plus QA frames. `duo-previews/`: 15 s Duo videos on Apple's 886 × 1920 canvas, plus QA frames.
  Previews are unedited screen recordings, only scaled to the store canvas: no device frame, bezel, rounded-corner mask, border, overlay or other styling. App Review rejected one under guideline 2.3.4 for device frames. Recording uses `--mask=ignored`; iPhone/iPad fill the canvas; Duo is fitted on plain black.

## Upload recovery

Upload, processing (waits up to 30 minutes) and review submission are separate stages. On an upload or processing error, check **Build Uploads** in App Store Connect before retrying. If the build processed but a later step failed, finish the draft or Public distribution in App Store Connect using the version and build number the lane printed; rerunning creates a new build. An interrupted screenshot replacement may need finishing in App Store Connect.

Failed runs keep the archive under `apple/build/`; successful processing saves dSYMs to `apple/build/symbols/<version>-<build>/` and removes the archive. Test and capture failures keep diagnostics.

## Mac

- **Signing:** automatic signing creates the Mac App Distribution and Mac Installer Distribution certificates during the archive.
- **Captures:** `mac_screenshots` drives the real app on this Mac through the `MacScreenshots` test plan (`MuntathirMacUITests`). Fastlane snapshot only drives simulators.
  - Before the first run, let macOS enable UI automation. Approve the prompt, or run `sudo automationmodetool enable-automationmode-without-authentication` once.
  - Keep the Mac awake, unlocked and untouched during the run.
  - With `--marketing-capture`, the app fixes the window at 1280 × 800 pt (`MuntathirApp.captureWindowSize`).
  - The script stages the Hadith, Supplications and translation databases into `Contents/Resources`, then re-signs the Debug app so the sandboxed app still launches.
- **Asset packs:** manifests list `iOS` and `macOS`. Running the Mac app from Xcode serves packs from `apple/build/AssetPacks/archives`, so run `just apple-packs` after changing a manifest. The release stops if Apple's processed pack version lacks either platform.
