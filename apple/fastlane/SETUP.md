# Apple release automation

Run commands from `apple/`. The project pins Fastlane 2.241.2 through Bundler; the machine-wide Fastlane installation is unchanged. `README.md` is Fastlane's generated lane reference. Keep project setup notes here.

```sh
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export BUNDLE_PATH=vendor/bundle
bundle install
bundle exec fastlane check
bundle exec fastlane marketing
```

## Lanes

- `screenshots`: capture Today, Calendar, Quran, and Qibla in all 14 supported store locales on iPhone 17 Pro Max, iPad Pro 13-inch (M5), and iPhone Duo.
- `watch_screenshots`: capture the real Watch prayer list in every store locale at 416 × 496, using a temporary Mecca connectivity cache that is restored afterward.
- `style`: add device bezels, gradient backgrounds and native text rendering for Arabic shaping.
- `previews`: record uploadable 15-second iPhone/iPad videos. Optional `previews devices:"iPhone Duo"` exports Duo videos for manual upload.
- `marketing`: capture/style all supported screenshots, including Duo, and generate uploadable previews. Unsupported Duo previews never block release.
- `tests`: run unit/UI regressions, excluding marketing captures.
- `readiness` / `readiness release:true`: read TestFlight / App Store prerequisites without changing remote data.
- `build`: export a signed IPA without uploading.
- `beta`: test, archive, upload, wait for processing and submit external Beta App Review for Public.
- `upload_beta ipa:/absolute/path.ipa`: retry upload of an already tested signed archive without rebuilding.
- `assets`: upload existing metadata and supported media without submitting review.
- `prepare build:NUMBER replace_screenshots:true`: replace screenshots, preserve existing previews and select a processed build without submitting review. Pass `automatic_release:true` only for a release approved for automatic publication.
- `upload_prepared ipa:/absolute/path.ipa`: upload an approved archive and replace media, preserving the review draft.
- `release`: test, generate media, archive, upload and submit App Review. Pass `build:NUMBER` to reuse a processed TestFlight build and generate fresh media. Publication is automatic after approval; pass `automatic_release:false` to hold a release manually.

## Capture settings and outputs

Captures use a clean isolated test preferences suite, Mecca, 23 October 2026, light appearance and local weather data. Fajr, Dhuhr and Maghrib are visible, with sunset enabled; all other optional times are hidden. This fixture is Debug-only and leaves normal app preferences unchanged. Quran source text is never modified. Screenshot captures read 94:6 from the bundled Quran database. Video captures and SwiftUI previews retain `exampleAyah` from `DailyAyahCard.swift`; each reference matches its text.

Screenshot captures use ayah 94:6 (index 6096). Quran capture builds stage downloaded translations locally, with English where no capture translation matches and Arabic alone in Arabic. Release bundles only Arabic and English. The capture runner stages the production Hadith database in its Debug bundle under the marketing launch flag; Release uses the hosted Hadith pack.

Standard devices use `SCREENSHOT_IOS_VERSION` (default 27.0), with iPhone and iPad captured concurrently for each locale. Duo uses `SCREENSHOT_DUO_IOS_VERSION` (default 27.2) in a separate snapshot pass without deleting the standard captures. Keep these passes sequential: Snapshot shares locale/launch-argument caches and shuts down booted simulators when preparing a pass. Install the runtimes in Xcode. Current snapshot captures use the native 1398 × 2034 Duo output; validation also accepts 2007 × 2853 and both landscape equivalents. Duo video recording explicitly selects the outer `primary` display; the simulator default can target the blank inner display. QA rejects blank frames. Capturing a single display does not establish layout correctness across folding transitions.

Screenshot headlines live in `marketing/headlines.json`. Standard iPhone bezels sit closer to headlines. Frameit provides standard phone/tablet bezels; Duo uses a neutral native bezel because frameit has no Duo bezel. The iPad capture fits the available 12.9-inch bezel without stretching and exports on the accepted 13-inch canvas. ImageMagick is required (`brew install imagemagick`). AppKit draws localized text, and final images are flattened with no alpha channel.

The Debug capture clock advances the actual Today UI continuously from sunrise to sunset. `ffmpeg` exports H.264/yuv420p video at 30 fps, with silent stereo AAC audio. `ffprobe` checks format and duration. Release builds exclude the capture controls.

Generated files live under ignored `build/marketing/`:

- `watch/`: native Watch captures required for the embedded companion.
- `raw/`: original screenshots and snapshot HTML summary.
- `frames/`: intermediate bezel images.
- `store/`: styled store screenshots, screenshots across iPhone, iPad, Duo and Apple Watch in 14 locales.
- `previews/`: 15-second standard iPhone/iPad videos and start/middle/end QA frames.
- `duo-previews/`: 15-second Duo videos at 886 × 1920, with QA frames. Duo keeps the native screen proportions inside a neutral frame and background on Apple’s required 886 × 1920 canvas.

**Duo preview upload limitation:** Fastlane 2.241.2 supports Duo screenshots but has no Duo preview upload type. Optional Duo videos are exported separately with `bundle exec fastlane previews devices:"iPhone Duo"` for manual App Store Connect upload. Keeping them outside automatic preview discovery prevents silent skipping or assignment to another device slot. An upload integration can move to Apple's App Asset Library when that work is requested; no undocumented preview enum is invented here.

Inspect all locales before upload: readable headlines, Arabic direction and joining, four visible prayer rows, no prompts, and Sun movement from start to finish. Simulator captures do not establish hardware compass, notifications or Watch behavior.

## Store metadata and private configuration

Manage names, subtitles, descriptions, keywords, promotional text, release notes, support/privacy URLs and the copyright notice under `metadata/`. `check` validates all 15 interface locales, interpolation placeholders, observance titles, permission strings, store text limits, and offline lane checks. `tests` also checks interface localization before invoking Xcode.

The app supports 15 interface locales, including Japanese. Metadata, screenshot headlines, captures, Watch captures, previews and TestFlight copy cover all 14 corresponding locales supported by Apple: Arabic, English, French, German, Indonesian, Italian, Japanese, Malay, Russian, Spanish, Turkish, Urdu, Simplified Chinese and Traditional Chinese. Apple does not support Persian listing metadata; translated copy is kept under `listing-drafts/fa/` outside the upload directory. Persian remains fully available in the app. See [Apple’s supported locales](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes). Preserve existing pricing, territories, categories, age rating, content-rights and privacy declarations.

Store API credentials at `~/.config/muntathir/fastlane.env`; field names are in `.env.local.example`. Protect the environment file, `.p8` key and private review JSON with `chmod 600`. `MUNTATHIR_FASTLANE_ENV_FILE` can select a different environment file. `MUNTATHIR_REVIEW_CONFIG` points to private review/contact/compliance values; `review.example.json` documents the shape. Never commit private keys or personal review details.

Readiness uses existing store fields plus explicitly managed local values. Missing required data blocks submission; no contacts, URLs or compliance answers are inferred. Existing Xcode automatic signing covers the app, Watch companion and extensions. There is no certificate-sharing repository. Version/build overrides are passed to Xcode without committing bumps: reuse the editable store version, otherwise choose the project version or next published patch; allocate the next TestFlight build number across version trains to avoid equivalent 1.0/1.0.0 collisions. Do not run simultaneous deployment lanes outside Actions.

## Dedicated GitHub runner and workflow

`bash apple/fastlane/setup-runner.sh` registers `Muntathir-local-Mac` with label `muntathir-deploy`, after `gh` authentication with repository administration access. It verifies GitHub's runner archive SHA-256, keeps isolated work directories under ignored `.local-ci/runner/`, and installs a user LaunchAgent. Other project runners are preserved. The service shares the logged-in GUI security session for signing Keychain access; the Mac must be awake with the session available.

Owner-created, same-repository non-draft PRs to `main` upload to TestFlight Public. Merging submits App Review with automatic publication after approval. Fork PRs are excluded. Owner-only manual dispatch supports individual lanes on a selected branch. Jobs serialize and never cancel active uploads. Artifacts retain captures, supported/manual preview exports, tests and deployment logs for 14 days. Never grant untrusted contributors execution access on this persistent signing machine.

Commit/push the workflow to activate it in GitHub. Binary upload, Apple processing and review submission are separate stages; an upload does not imply approval. TestFlight processing times out after 30 minutes. Check App Store Connect before retrying, and use `assets` to retry metadata/media without rebuilding. Existing screenshot sets for uploaded locales are cleared before replacement uploads; local media validation runs first. Preview replacement is controlled separately.

Processed asset packs available for internal testing do not satisfy the external TestFlight gate. Apple requires submitting a build before submitting its associated packs for external review. Use `build` to export an IPA, upload it for internal testing through Transporter, then submit the processed pack versions in App Store Connect. Rerun `readiness` after approval. See [Apple’s asset-pack testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs).

References: [Fastlane 2.241.2](https://github.com/fastlane/fastlane/releases/tag/2.241.2), [snapshot](https://docs.fastlane.tools/actions/snapshot/), [frameit](https://docs.fastlane.tools/actions/frameit/), [App Asset Library release notes](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes).

Apple requires 15–30 seconds for App Store previews. The capture clock advances the full Sun movement over 15 seconds. Today and daily ayah share one screenshot and headline. Duo screenshots clip to rounded corners inside a dark bezel.

Screenshot validation reads the required screen names from `marketing/headlines.json`. Capture builds have their own cache under `build/marketing/`, separate from regression tests.

## Replacement submission (November 2026)

Current release target: 1.1.0, with the next available build number. Xcode 27 JSON projects require native `xcodebuild archive` and `-exportArchive`; Fastlane’s project parser cannot read them. The build lane reads the version through Xcode build settings.

Arabic and English Quran databases ship in the app and widget. The other translations use the hosted `quran-translations` pack, and Hadith uses `hadith`. Upload the validated archives with `bundle exec ruby fastlane/asset_pack_delivery.rb --upload`. The release lane attaches processed versions of required packs that are unavailable on the App Store. Submit new packs separately for external Beta App Review in App Store Connect after submitting the beta build.

`beta_notes/<locale>.txt` contains What to Test, separate from public release notes. After uploading the signed IPA once, run `public_beta build:NUMBER` to distribute that existing build to Public without uploading again.

Screenshots stage the unchanged production Hadith database in the Debug capture bundle only. Marketing launches bypass hosted download events; Release excludes both the staged database and the capture override. Capture all five screens in each supported locale and device. Keep previews only after validating their formats and reviewing their content.

The requested publication policy is automatic after approval. Existing pre-order configuration may lock Apple’s release-type field; verify the actual remote setting before submission rather than assuming a lane option changed it.

## Build artifact lifecycle

Successful test and capture runs remove their own DerivedData directories. Failed runs
keep their artifacts for diagnosis; run `bundle exec fastlane cleanup` once finished.
The cleanup lane touches only its listed project-local caches, not global Xcode data,
IPAs, test reports, screenshots, previews, or asset packs. Do not run cleanup during a build.
Custom screenshot DerivedData paths remain caller-owned.

After a successful archive export and bundle validation, dSYMs move to
`build/symbols/<version>-<build>/`, then the archive and archive build cache are removed.
The signed IPA stays available for upload retries. Failed exports retain the archive.
Keep symbols for crash symbolication. Existing manually created archives are not pruned.
Preview source recordings are removed once their final video and QA frames validate.

## Search-by-meaning release copy

Metadata and beta notes spotlight the optional online fallback in Quran/Hadith search.
Local search and book/chapter scopes remain unchanged. There is no separate Search tab.
The copy is prepared locally in all store locales (Persian remains a listing draft);
metadata changes are not uploaded until an explicit release/upload lane runs.

### Version 1.1.0 automation

Your non-draft, same-repository PRs to `main` run `beta` when opened, updated,
reopened, or marked ready: validate, test, archive, upload to TestFlight, and request
Public external beta review. All changed paths qualify. Fork PRs are excluded.

Merging runs `release` on the merge commit: validate, test, generate media, archive,
upload, and submit App Store review. Publication is automatic after Apple approval.
Deployments queue on this Mac; its runner and signing session must be available.
Push the workflow to GitHub to activate changes. Workflow artifacts include symbols
for 14 days; retain local symbols for older builds.

Fastlane 2.241.2 was checked for Duo support: screenshot support remains available, but its released preview types still omit Duo. Duo preview exports remain separate for manual upload.

Capture runtime and locale/layout rules are maintained in `support.rb`. Screenshot passes remain sequential to avoid Snapshot cache collisions. Duo-specific display selection, size validation and neutral framing remain necessary compatibility handling. Routine releases need no separate Duo command.

The isolated runner checkout stages its ignored Hadith database from `MUNTATHIR_CONTENT_ROOT` (default `~/code/Muntathir`). Corpus validation runs before tests; the public search URL is configured without copying credentials. Prepare this content workspace before deployment.
