# Local releases

Install the pinned Fastlane bundle from the repository root. On macOS with Homebrew Ruby:

```sh
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export BUNDLE_PATH=vendor/bundle
bundle install
```

| Command | Purpose |
| --- | --- |
| `just version X.Y.Z` | Set the shared marketing version |
| `just lane ios beta` | Upload a build for the Public TestFlight group |
| `just lane android beta` | Upload a build to Play internal testing |
| `just lane ios release` | Submit an existing TestFlight build for App Review |

Promote Android builds to production manually in Play Console.

## Production tags

After the version goes live on a platform, create an annotated Git tag on the commit that produced its shipped binary and push the tag to GitHub. Use `ios/vX.Y.Z` or `android/vX.Y.Z`. Both tags can point to the same commit. Use TestFlight build numbers and Play version codes to identify beta builds.

## Asset packs

Run `just apple-packs` to package Apple archives, `just android-packs` to stage Play Asset Delivery files, or `just packs-check` to validate the databases. Each command defaults to `all` and accepts `hadith`, `supplications`, `quran`, or `rulings` to select one content family.

## Apple

Run `just lane ios check` for local release checks. See [Apple release and capture instructions](ios/SETUP.md) for signing, store metadata, and marketing media.

## Android

Configure the Play upload key in `android/local.properties` or Gradle properties. The lane uses the
Play service account JSON at `~/.android/muntathir-upload/play-publisher.json` by default.
Set `SUPPLY_JSON_KEY` to override that path.

```sh
just lane android beta aab:/absolute/path/app-release.aab validate_only:true
just lane android beta aab:/absolute/path/app-release.aab draft:true
```

When building an AAB, the lane reads version codes from the internal, alpha, beta, and production tracks and uses the highest code plus one (1 for an empty app). Run one Android publisher at a time. A supplied `aab:` keeps its embedded version code.

The lane stages the asset packs, builds a signed AAB, and publishes it
to Play internal testing. Pass `aab:` to reuse a signed bundle, `validate_only:true`
to validate it, or `draft:true` to save it as a draft. The lane skips listing
metadata and screenshots. Play listing text lives in `fastlane/android/metadata/`.

### Store screenshots

Start a dedicated Pixel 10 emulator at its native 1080 × 2424 resolution and stage the Android content databases with `just android-packs`. The capture lane installs the debug app and its instrumentation APK and copies the Hadith and Supplications libraries into the emulator. The styling lane uses the Pixel 10 skin installed by Android Studio and exports 1080 × 1920 Play images. Recapture screenshots before styling if they were made at the previous resolution. Set `ANDROID_SERIAL` when multiple emulators are connected.

```sh
just lane android screenshots languages:ar,en,fa
just lane android style languages:ar,en,fa
```

Omit `languages` to generate all 15 app locales on either platform. Review the eight ordered PNGs under each locale’s `images/phoneScreenshots` folder. The Apple and Android styling lanes use the same scene list, localized headlines and compositor.
