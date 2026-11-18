# Local releases

Install the pinned Fastlane bundle from the repository root. On macOS with Homebrew Ruby:

```sh
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export BUNDLE_PATH=vendor/bundle
bundle install
```

Use `just version X.Y.Z` to set the visible release version for both platforms. Apple’s build number and Android’s version code are managed separately.

## Apple

Run `just lane ios check` for local release checks. See [Apple release and capture instructions](ios/SETUP.md) for signing, store metadata, and marketing media.

## Android

Set `SUPPLY_JSON_KEY` to the path of a readable Play service account credentials JSON. Pass a signed AAB to the internal lane.

```sh
just lane android internal aab:/absolute/path/app-release.aab
just lane android internal aab:/absolute/path/app-release.aab draft:true
```

The first command validates the bundle with Google Play. The second saves it as an internal-track draft. Both commands skip listing metadata and screenshots. Play listing text lives in `fastlane/android/metadata/`.

### Store screenshots

Start a dedicated Pixel emulator and stage the Android content databases with `just android-packs`. The capture lane installs the debug app and its instrumentation APK, copies the Hadith and Supplications libraries into the emulator, and uses a 1080 × 2160 display for the Pixel frame. Set `ANDROID_SERIAL` when multiple emulators are connected.

```sh
just lane android screenshots languages:ar,en,fa
just lane android style languages:ar,en,fa
```

Omit `languages` to generate all 15 app locales on either platform. Review the eight ordered PNGs under each locale’s `images/phoneScreenshots` folder. The Apple and Android styling lanes use the same scene list, localized headlines and compositor.
