fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios check

```sh
[bundle exec] fastlane ios check
```

Validate local metadata and release lanes without Apple access

### ios tests

```sh
[bundle exec] fastlane ios tests
```

Run unit and UI regression tests, excluding marketing captures

### ios cleanup

```sh
[bundle exec] fastlane ios cleanup
```

Remove disposable local build caches; keep IPAs, symbols, media and diagnostics

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture localized iPhone, iPad and Duo screenshots

### ios style

```sh
[bundle exec] fastlane ios style
```

Style raw screenshots with frames, backgrounds and localized headlines

### ios previews

```sh
[bundle exec] fastlane ios previews
```

Record continuous sunrise-to-sunset simulator previews in every store locale

### ios watch_screenshots

```sh
[bundle exec] fastlane ios watch_screenshots
```

Capture required localized Apple Watch store screenshots

### ios web_media

```sh
[bundle exec] fastlane ios web_media
```

Export Arabic/English website screenshots as WebP and previews as WebM

### ios marketing

```sh
[bundle exec] fastlane ios marketing
```

Generate all screenshots, App Preview videos and website media locally

### ios testflight_public

```sh
[bundle exec] fastlane ios testflight_public
```

Test on iPhone and submit a new build to TestFlight Public

### ios app_store

```sh
[bundle exec] fastlane ios app_store
```

Test on iPhone and iPad, refresh the listing, and submit the TestFlight build for automatic App Store release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
