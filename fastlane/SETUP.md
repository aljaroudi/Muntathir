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
