# Local releases

Install the pinned Fastlane bundle from the repository root (macOS, Homebrew Ruby):

```sh
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export BUNDLE_PATH=vendor/bundle
bundle install
```

| Command | Purpose |
| --- | --- |
| `just version X.Y.Z` | Set the shared marketing version |
| `just lane ios beta` | Upload a build to the Public TestFlight group |
| `just lane ios release` | Submit an existing TestFlight build for App Review |
| `just lane android beta` | Upload a build to Play closed testing |

Promote Android builds to production manually in Play Console.

**Production tags:** once a version is live, push an annotated tag `ios/vX.Y.Z` or `android/vX.Y.Z` on the commit that produced the shipped binary (both may share a commit). Beta builds are identified by TestFlight build number or Play version code.

**Asset packs:** `just apple-packs` (Apple archives), `just android-packs` (Play Asset Delivery files), `just packs-check` (validate databases). Each takes `all` (default), `hadith`, `supplications`, `quran` or `rulings`.

## Apple

`just lane ios check` runs local release checks. Signing, store metadata and marketing media: [ios/SETUP.md](ios/SETUP.md).

## Android

- Upload key: `android/local.properties` or Gradle properties (`UPLOAD_STORE_FILE`, `UPLOAD_STORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, `UPLOAD_KEY_PASSWORD`).
- Play service account JSON: `~/.android/muntathir-upload/play-publisher.json`, or set `SUPPLY_JSON_KEY`.

`beta` stages the asset packs, builds a signed AAB and publishes it to the closed testing track (`alpha`, Play's default closed track; pass `track:<name>` for a custom closed track or `track:internal`). It skips listing metadata and screenshots (listing text is in `fastlane/android/metadata/`).

```sh
just lane android beta aab:/absolute/path/app-release.aab validate_only:true
just lane android beta aab:/absolute/path/app-release.aab draft:true
```

- `aab:` reuses a signed bundle and keeps its embedded version code. Otherwise the version code is the highest across internal, alpha, beta and production plus one (1 for an empty app).
- `validate_only:true` validates only; `draft:true` saves a draft.
- Run one Android publisher at a time.

### Store screenshots

Start a dedicated Pixel 10 emulator at its native 1080 × 2424 and run `just android-packs`. The capture lane installs the debug and instrumentation APKs and copies the Hadith and Supplications libraries onto the emulator. `style` uses Android Studio's Pixel 10 skin and exports 1080 × 1920 Play images. Set `ANDROID_SERIAL` when several emulators are connected.

```sh
just lane android screenshots languages:ar,en,fa
just lane android style languages:ar,en,fa
```

Omit `languages` for all 15 locales (same on iOS). Review the eight PNGs in each locale's `images/phoneScreenshots`. Apple and Android styling share the scene list, headlines and compositor.
