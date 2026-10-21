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

- `screenshots`: capture three screens in English and Arabic on iPhone 17 Pro Max, iPad Pro 13-inch (M5), and iPhone Duo.
- `style`: add device bezels, gradient backgrounds and native text rendering for Arabic shaping.
- `previews`: record 15-second sunrise-to-sunset videos on all three devices.
- `marketing`: run capture, styling and preview generation.
- `tests`: run unit/UI regressions, excluding marketing captures.
- `readiness` / `readiness release:true`: read TestFlight / App Store prerequisites without changing remote data.
- `build`: export a signed IPA without uploading.
- `beta`: test, archive, upload, wait for processing and submit external Beta App Review for Public.
- `assets`: upload existing metadata and supported media without submitting review.
- `release`: test, generate media, archive, upload and submit App Review. Publication stays manual after approval.

## Capture settings and outputs

Captures use a clean isolated test preferences suite, Mecca, 21 October 2026, light appearance and local weather data. Fajr, Dhuhr and Maghrib are visible, with sunset enabled; all other optional times are hidden. This fixture is Debug-only and leaves normal app preferences unchanged. Quran source text is never modified.

Standard devices use `SCREENSHOT_IOS_VERSION` (default 27.0). Duo uses iOS 27.1 in a separate snapshot pass without deleting the standard captures. Install the runtimes in Xcode. Current snapshot captures use the native 1398 × 2034 Duo output; validation also accepts 2007 × 2853 and both landscape equivalents. Duo video recording explicitly selects the outer `primary` display; the simulator default can target the blank inner display. QA rejects blank frames. Capturing a single display does not establish layout correctness across folding transitions.

Screenshot headlines live in `marketing/headlines.json`. Standard iPhone bezels sit closer to headlines. Frameit provides standard phone/tablet bezels; Duo uses a neutral native bezel because frameit has no Duo bezel. The iPad capture fits the available 12.9-inch bezel without stretching and exports on the accepted 13-inch canvas. ImageMagick is required (`brew install imagemagick`). AppKit draws localized text, and final images are flattened with no alpha channel.

The Debug capture clock advances the actual Today UI continuously from sunrise to sunset. `ffmpeg` exports H.264/yuv420p video at 30 fps, with silent stereo AAC audio. `ffprobe` checks format and duration. Release builds exclude the capture controls.

Generated files live under ignored `build/marketing/`:

- `raw/`: original screenshots and snapshot HTML summary.
- `frames/`: intermediate bezel images.
- `store/`: styled store screenshots, 18 files across the three devices and two locales.
- `previews/`: 15-second standard iPhone/iPad videos and start/middle/end QA frames.
- `duo-previews/`: 15-second Duo videos at 886 × 1920, with QA frames.

**Duo preview upload limitation:** Fastlane 2.241.1 supports Duo screenshots but has no Duo preview upload type. Duo videos are exported separately for manual App Store Connect upload. Keeping them outside automatic preview discovery prevents silent skipping or assignment to another device slot. An upload integration can move to Apple's App Asset Library when that work is requested; no undocumented preview enum is invented here.

Inspect all locales before upload: readable headlines, Arabic direction and joining, four visible prayer rows, no prompts, and Sun movement from start to finish. Simulator captures do not establish hardware compass, proximity counting, notifications or Watch behavior.

## Store metadata and private configuration

Manage names, subtitles, descriptions, keywords, promotional text, release notes, support/privacy URLs and the copyright notice under `metadata/`. `check` enforces localized text limits. Preserve existing pricing, territories, categories, age rating, content-rights and privacy declarations.

Store API credentials at `~/.config/muntathir/fastlane.env`; field names are in `.env.local.example`. Protect the environment file, `.p8` key and private review JSON with `chmod 600`. `MUNTATHIR_FASTLANE_ENV_FILE` can select a different environment file. `MUNTATHIR_REVIEW_CONFIG` points to private review/contact/compliance values; `review.example.json` documents the shape. Never commit private keys or personal review details.

Readiness uses existing store fields plus explicitly managed local values. Missing required data blocks submission; no contacts, URLs or compliance answers are inferred. Existing Xcode automatic signing covers the app, Watch companion and extensions. There is no certificate-sharing repository. Version/build overrides are passed to Xcode without committing bumps: reuse the editable store version, otherwise choose the project version or next published patch; allocate the next TestFlight build number. Do not run simultaneous deployment lanes outside Actions.

## Dedicated GitHub runner and workflow

`bash apple/fastlane/setup-runner.sh` registers `Muntathir-local-Mac` with label `muntathir-deploy`, after `gh` authentication with repository administration access. It verifies GitHub's runner archive SHA-256, keeps isolated work directories under ignored `.local-ci/runner/`, and installs a user LaunchAgent. Other project runners are preserved. The service shares the logged-in GUI security session for signing Keychain access; the Mac must be awake with the session available.

Owner-created, same-repository non-draft PRs to `main` upload to TestFlight Public. Merging submits App Review; release remains manual. Fork PRs are excluded. Manual dispatch on `main` supports individual lanes. Jobs serialize and never cancel active uploads. Artifacts retain captures, supported/manual preview exports, tests and deployment logs for 14 days. Never grant untrusted contributors execution access on this persistent signing machine.

Commit/push the workflow to activate it in GitHub. Binary upload, Apple processing and review submission are separate stages; an upload does not imply approval. TestFlight processing times out after 30 minutes. Check App Store Connect before retrying, and use `assets` to retry metadata/media without rebuilding. Existing remote assets are not cleared automatically; remove superseded sets manually where necessary to stay within Apple limits.

References: [Fastlane 2.241.1](https://github.com/fastlane/fastlane/releases/tag/2.241.1), [snapshot](https://docs.fastlane.tools/actions/snapshot/), [frameit](https://docs.fastlane.tools/actions/frameit/), [App Asset Library release notes](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes).

Apple requires 15–30 seconds for App Store previews. The capture clock advances the full Sun movement over 15 seconds. Today and daily ayah share one screenshot and headline. Duo screenshots clip to rounded corners inside a dark bezel.
