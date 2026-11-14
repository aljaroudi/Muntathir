# Manual Apple releases

Run from `apple/` on the signing Mac. Use the pinned Fastlane version through Bundler.

```sh
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export BUNDLE_PATH=vendor/bundle
bundle install
bundle exec fastlane check
```

## Release commands

```sh
bundle exec fastlane testflight_public
bundle exec fastlane app_store
```

- **TestFlight Public** runs the unit/UI regression suite on the newest compatible installed iPhone simulator and submits the build to the external `Public` group with localized What to Test. TestFlight invitations pull screenshots from the latest App Store version ready for distribution. Screenshot capture and upload run in the App Store lane. [Apple’s TestFlight screenshot rules](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- **App Store** runs the suite on that iPhone and the configured iPad Pro. It uploads fresh screenshots and listing metadata, keeps existing preview videos, and submits the new build for automatic publication after approval.
- Both commands are local and manual. The GitHub Actions deployment workflow is removed. Wait for one release to finish before starting another checkout or uploading the same version elsewhere. A checkout lock prevents overlapping release commands in the same working directory.

The workflow deletion takes effect on GitHub once it reaches the default branch. Until then, disable the old **Local Apple deployment** workflow in Actions before opening or merging a PR that would trigger it.

## Before running

1. Set the marketing version in Xcode and, for the App Store lane, manually create the matching editable iOS draft in App Store Connect. Keep the project build number at `1`. Xcode assigns the final build number during upload. [Apple’s build-number rules](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
2. Update `beta_notes/<locale>.txt` for What to Test or `metadata/<locale>/release_notes.txt` for What’s New. Each lane compares its notes against the latest Public build or live App Store version. All 14 store locales must pass validation and at least one note must differ when Apple has prior notes. Use `force:true` on the release command to allow intentionally unchanged notes. The draft, tests, archive, screenshots, and metadata validity checks still run.
3. Configure the App Store Connect key in `~/.config/muntathir/fastlane.env` using `.env.local.example`. Set `MUNTATHIR_REVIEW_CONFIG` to a private JSON file for export compliance and any missing review fields. See `review.example.json`. Protect the credentials and review files with `chmod 600`. Automatic signing covers the app, Watch companion, and extensions. Set up the external group named `Public` and enable its public link in App Store Connect if needed.
4. Install Apple Transporter for asset uploads. For the App Store lane, also install the capture simulators and runtimes below, a shutdown Apple Watch Series 12 (46mm) simulator, ImageMagick, and FFmpeg. Generate the local content databases and validate the assets with `python3 AssetPacks/assets.py validate --content all`.

Both release lanes compare the manifest and payload files with each cached archive under `build/AssetPacks/archives/`. They rebuild changed packs, update the bundled download-size estimates when repackaging, and reuse an Apple version whenever its checksum matches the archive. Keep the originally uploaded archives on the release Mac. A missing archive, or an older remote version without a comparable checksum, can require a one-time upload to establish the match. The App Store lane attaches the exact processed versions that differ from the live packs. After submitting a Public build, submit the listed pack versions for external testing in App Store Connect. [Apple’s asset-pack testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs)

Manage localized names, descriptions, keywords, promotional text, support/privacy URLs, and copyright under `metadata/`. Persian interface copy is supported and its store copy stays under `listing-drafts/fa/`. Keep private review contacts in App Store Connect or the private review JSON.

## Local commands

- `check` validates localization, metadata, screenshot configuration, and lane behavior offline.
- `tests` runs the local unit/UI regressions on one iPhone. Both release lanes run screenshot capture separately.
- `screenshots`, `watch_screenshots`, and `style` capture and compose the five iOS screens and the Watch prayer screen in all 14 store locales.
- `previews` generates optional videos. `previews devices:"iPhone Duo"` generates Duo videos for manual upload.
- `marketing` refreshes screenshots and generates the standard previews locally.

## Capture settings and outputs

Captures use a clean isolated test preferences suite, Mecca, 23 October 2026, light appearance and local weather data. Fajr, Dhuhr and Maghrib are visible, with sunset enabled; all other optional times are hidden. This fixture is Debug-only and leaves normal app preferences unchanged. Quran source text is never modified. Screenshot captures read 94:6 from the bundled Quran database. Video captures and SwiftUI previews retain `exampleAyah` from `DailyAyahCard.swift`; each reference matches its text.

Screenshot captures use ayah 94:6 (index 6096). Quran capture builds stage downloaded translations locally, with English where no capture translation matches and Arabic alone in Arabic. Release bundles only Arabic and English. The capture runner stages the production Hadith database in its Debug bundle under the marketing launch flag; Release uses the hosted Hadith pack.

Standard devices use `SCREENSHOT_IOS_VERSION` (default 27.0), with iPhone and iPad captured concurrently for each locale. Duo uses `SCREENSHOT_DUO_IOS_VERSION` (default 27.2) in a separate snapshot pass without deleting the standard captures. Keep these passes sequential: Snapshot shares locale/launch-argument caches and shuts down booted simulators when preparing a pass. Install the runtimes in Xcode. Current snapshot captures use the native 1398 × 2034 Duo output; validation also accepts 2007 × 2853 and both landscape equivalents. Duo video recording explicitly selects the outer `primary` display; the simulator default can target the blank inner display. QA rejects blank frames. Capturing a single display does not establish layout correctness across folding transitions.

Edit [the screenshot config](marketing/screenshots.json) to set the ordered screen IDs, headlines for each locale, brand text, and two RGB gradient stops. Numbered screen IDs control upload order and match the snapshot names in `MarketingScreenshotTests`. The Watch slot captures the native app. Standard iPhone bezels sit closer to headlines. Frameit provides standard phone/tablet bezels; Duo uses a neutral native bezel because frameit has no Duo bezel. The iPad capture fits the available 12.9-inch bezel without stretching and exports on the accepted 13-inch canvas. ImageMagick is required (`brew install imagemagick`). AppKit draws localized text, and final images are flattened with no alpha channel.

The Debug capture clock advances the actual Today UI continuously from sunrise to sunset. `ffmpeg` exports H.264/yuv420p video at 30 fps, with silent stereo AAC audio. `ffprobe` checks format and duration. Release builds exclude the capture controls.

Generated files live under ignored `build/marketing/`:

- `watch/`: native Watch captures required for the embedded companion.
- `raw/`: original screenshots and snapshot HTML summary.
- `frames/`: intermediate bezel images.
- `store/`: styled store screenshots, screenshots across iPhone, iPad, Duo and Apple Watch in 14 locales.
- `previews/`: 15-second standard iPhone/iPad videos and start/middle/end QA frames.
- `duo-previews/`: 15-second Duo videos at 886 × 1920, with QA frames. Duo keeps the native screen proportions inside a neutral frame and background on Apple’s required 886 × 1920 canvas.

**Duo preview upload limitation:** Fastlane 2.241.2 supports Duo screenshots but has no Duo preview upload type. Optional Duo videos are exported separately with `bundle exec fastlane previews devices:"iPhone Duo"` for manual App Store Connect upload. Keeping them outside automatic preview discovery prevents silent skipping or assignment to another device slot. An upload integration can move to Apple's App Asset Library when that work is requested; no undocumented preview enum is invented here.

For visual QA, run the local media lanes and inspect headline readability, Arabic joining and direction, the four prayer rows, and the Sun movement in previews. Simulator captures do not establish hardware compass, notifications or Watch behavior.

## Upload recovery and artifacts

Binary upload, Apple processing, and review submission are separate stages. If upload or processing errors, inspect **Build Uploads** in App Store Connect before retrying. Processing waits up to 30 minutes. If the expected build processed and a later step failed, finish its draft or Public distribution in App Store Connect using the exact version and build number printed by the lane. Rerunning a release command creates a new build. Screenshot replacement may need to be completed in App Store Connect if an upload stops partway through.

Failed uploads and processing retain the archive under `build/`. Successful processing saves dSYMs under `build/symbols/<version>-<build>/` and removes that archive. Test and capture failures retain local diagnostics. `bundle exec fastlane cleanup` removes project-local disposable caches after the run.
