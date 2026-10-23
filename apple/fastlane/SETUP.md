# Apple release automation

Run commands from `apple/`. The project pins Fastlane 2.241.1 through Bundler; the machine-wide Fastlane installation is unchanged. `README.md` is Fastlane's generated lane reference. Keep project setup notes here.

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
- `previews`: record 15-second sunrise-to-sunset videos on all three devices.
- `marketing`: run capture, styling and preview generation.
- `tests`: run unit/UI regressions, excluding marketing captures.
- `readiness` / `readiness release:true`: read TestFlight / App Store prerequisites without changing remote data.
- `build`: export a signed IPA without uploading.
- `beta`: test, archive, upload, wait for processing and submit external Beta App Review for Public.
- `upload_beta ipa:/absolute/path.ipa`: retry upload of an already tested signed archive without rebuilding.
- `assets`: upload existing metadata and supported media without submitting review.
- `prepare build:NUMBER`: upload metadata/media and select a processed TestFlight build, leaving review submission pending.
- `upload_prepared ipa:/absolute/path.ipa`: upload an approved archive and replace media, preserving the review draft.
- `release`: test, generate media, archive, upload and submit App Review. Publication stays manual after approval.

## Capture settings and outputs

Captures use a clean isolated test preferences suite, Mecca, 23 October 2026, light appearance and local weather data. Fajr, Dhuhr and Maghrib are visible, with sunset enabled; all other optional times are hidden. This fixture is Debug-only and leaves normal app preferences unchanged. Quran source text is never modified. Screenshot captures read 94:6 from the bundled Quran database. Video captures and SwiftUI previews retain `exampleAyah` from `DailyAyahCard.swift`; each reference matches its text.

Screenshot captures use ayah 94:6 (index 6096). Quran uses each locale’s translation, with English for Japanese and Arabic alone for Arabic. The capture runner stages unchanged asset-pack database inputs in its Debug bundle, guarded by marketing-only launch arguments; Simulator pack delivery otherwise needs a TLS mock server and developer override. Release builds continue using real asset packs.

Standard devices use `SCREENSHOT_IOS_VERSION` (default 27.0). Duo uses iOS 27.1 in a separate snapshot pass without deleting the standard captures. Install the runtimes in Xcode. Current snapshot captures use the native 1398 × 2034 Duo output; validation also accepts 2007 × 2853 and both landscape equivalents. Duo video recording explicitly selects the outer `primary` display; the simulator default can target the blank inner display. QA rejects blank frames. Capturing a single display does not establish layout correctness across folding transitions.

Screenshot headlines live in `marketing/headlines.json`. Standard iPhone bezels sit closer to headlines. Frameit provides standard phone/tablet bezels; Duo uses a neutral native bezel because frameit has no Duo bezel. The iPad capture fits the available 12.9-inch bezel without stretching and exports on the accepted 13-inch canvas. ImageMagick is required (`brew install imagemagick`). AppKit draws localized text, and final images are flattened with no alpha channel.

The Debug capture clock advances the actual Today UI continuously from sunrise to sunset. `ffmpeg` exports H.264/yuv420p video at 30 fps, with silent stereo AAC audio. `ffprobe` checks format and duration. Release builds exclude the capture controls.

Generated files live under ignored `build/marketing/`:

- `watch/`: native Watch captures required for the embedded companion.
- `raw/`: original screenshots and snapshot HTML summary.
- `frames/`: intermediate bezel images.
- `store/`: styled store screenshots, 182 files across iPhone, iPad, Duo and Apple Watch in 14 locales.
- `previews/`: 15-second standard iPhone/iPad videos and start/middle/end QA frames.
- `duo-previews/`: 15-second Duo videos at 886 × 1920, with QA frames. Duo keeps the native screen proportions inside a neutral frame and background on Apple’s required 886 × 1920 canvas.

**Duo preview upload limitation:** Fastlane 2.241.1 supports Duo screenshots but has no Duo preview upload type. Duo videos are exported separately for manual App Store Connect upload. Keeping them outside automatic preview discovery prevents silent skipping or assignment to another device slot. An upload integration can move to Apple's App Asset Library when that work is requested; no undocumented preview enum is invented here.

Inspect all locales before upload: readable headlines, Arabic direction and joining, four visible prayer rows, no prompts, and Sun movement from start to finish. Simulator captures do not establish hardware compass, notifications or Watch behavior.

## Store metadata and private configuration

Manage names, subtitles, descriptions, keywords, promotional text, release notes, support/privacy URLs and the copyright notice under `metadata/`. `check` validates all 15 interface locales, interpolation placeholders, observance titles, permission strings, store text limits, and offline lane checks. `tests` also checks interface localization before invoking Xcode.

The app supports 15 interface locales, including Japanese. Metadata, screenshot headlines, captures, Watch captures, previews and TestFlight copy cover all 14 corresponding locales supported by Apple: Arabic, English, French, German, Indonesian, Italian, Japanese, Malay, Russian, Spanish, Turkish, Urdu, Simplified Chinese and Traditional Chinese. Apple does not support Persian listing metadata; translated copy is kept under `listing-drafts/fa/` outside the upload directory. Persian remains fully available in the app. See [Apple’s supported locales](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes). Preserve existing pricing, territories, categories, age rating, content-rights and privacy declarations.

Store API credentials at `~/.config/muntathir/fastlane.env`; field names are in `.env.local.example`. Protect the environment file, `.p8` key and private review JSON with `chmod 600`. `MUNTATHIR_FASTLANE_ENV_FILE` can select a different environment file. `MUNTATHIR_REVIEW_CONFIG` points to private review/contact/compliance values; `review.example.json` documents the shape. Never commit private keys or personal review details.

Readiness uses existing store fields plus explicitly managed local values. Missing required data blocks submission; no contacts, URLs or compliance answers are inferred. Existing Xcode automatic signing covers the app, Watch companion and extensions. There is no certificate-sharing repository. Version/build overrides are passed to Xcode without committing bumps: reuse the editable store version, otherwise choose the project version or next published patch; allocate the next TestFlight build number across version trains to avoid equivalent 1.0/1.0.0 collisions. Do not run simultaneous deployment lanes outside Actions.

## Dedicated GitHub runner and workflow

`bash apple/fastlane/setup-runner.sh` registers `Muntathir-local-Mac` with label `muntathir-deploy`, after `gh` authentication with repository administration access. It verifies GitHub's runner archive SHA-256, keeps isolated work directories under ignored `.local-ci/runner/`, and installs a user LaunchAgent. Other project runners are preserved. The service shares the logged-in GUI security session for signing Keychain access; the Mac must be awake with the session available.

Owner-created, same-repository non-draft PRs to `main` upload to TestFlight Public. Merging submits App Review; release remains manual. Fork PRs are excluded. Manual dispatch on `main` supports individual lanes. Jobs serialize and never cancel active uploads. Artifacts retain captures, supported/manual preview exports, tests and deployment logs for 14 days. Never grant untrusted contributors execution access on this persistent signing machine.

Commit/push the workflow to activate it in GitHub. Binary upload, Apple processing and review submission are separate stages; an upload does not imply approval. TestFlight processing times out after 30 minutes. Check App Store Connect before retrying, and use `assets` to retry metadata/media without rebuilding. Existing remote assets are not cleared automatically; remove superseded sets manually where necessary to stay within Apple limits.

Processed asset packs available for internal testing do not satisfy the external TestFlight gate. Apple requires submitting a build before submitting its associated packs for external review. Use `build` to export an IPA, upload it for internal testing through Transporter, then submit the processed pack versions in App Store Connect. Rerun `readiness` after approval. See [Apple’s asset-pack testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs).

References: [Fastlane 2.241.1](https://github.com/fastlane/fastlane/releases/tag/2.241.1), [snapshot](https://docs.fastlane.tools/actions/snapshot/), [frameit](https://docs.fastlane.tools/actions/frameit/), [App Asset Library release notes](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes).

Apple requires 15–30 seconds for App Store previews. The capture clock advances the full Sun movement over 15 seconds. Today and daily ayah share one screenshot and headline. Duo screenshots clip to rounded corners inside a dark bezel.

The Quran capture opens Al-Ikhlas with translation set to None, so all localized interfaces can be captured offline without depending on asset-pack downloads. Screenshot validation reads the required screen names from `marketing/headlines.json`.

Snapshot builds use `build/marketing/DerivedData` so they do not share a build cache with regression tests.

## Reviewed local submission

The four app screenshots are Today, Calendar, Quran, and Qibla. Marketing screenshots use Quran 94:6 and the October 2026 calendar. The sunrise-to-sunset preview keeps its original verse and sequence. Run screenshots, watch_screenshots, style, previews, tests, and build locally; inspect and approve the generated media before running `upload_prepared ipa:build/Muntathir.ipa`. This lane reuses the editable version, replaces screenshots and previews, and uploads the archive. After processing, select the uploaded build and submit the existing draft through App Store Connect, keeping release manual. Fastlane refuses drafts containing existing asset-pack items, so use the web UI for this final step. It does not regenerate approved media. Existing Ready for Review drafts are reused.

For a first App Store submission, packs must have processed iOS versions; external TestFlight approval is a separate gate. Existing published apps still require live App Store packs. During this update, GitHub's Apple deployment workflow is disabled remotely until the owner merges and re-enables it. Do not push or create a PR as part of the local submission.

For this submission, defer `quran-ms-basmeih`, `quran-ur-jawadi`, and `quran-zh-majian` (Malay, Urdu, Traditional Chinese). Keep the other ten packs with the app submission. Submit the deferred packs after app approval and before manually releasing the app.
