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

Validate local metadata and automation checks without Apple access

### ios tests

```sh
[bundle exec] fastlane ios tests
```

Run unit and UI regression tests, excluding marketing captures

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

### ios marketing

```sh
[bundle exec] fastlane ios marketing
```

Generate all screenshots and App Preview videos locally

### ios readiness

```sh
[bundle exec] fastlane ios readiness
```

Read App Store readiness without changing remote settings

### ios build

```sh
[bundle exec] fastlane ios build
```

Validate signing and export an IPA without uploading

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Test, archive, upload and submit Public external Beta App Review

### ios upload_beta

```sh
[bundle exec] fastlane ios upload_beta
```

Retry TestFlight upload of an already tested and signed IPA

### ios assets

```sh
[bundle exec] fastlane ios assets
```

Upload current metadata and media without submitting App Review

### ios prepare

```sh
[bundle exec] fastlane ios prepare
```

Upload metadata/media and select a processed TestFlight build without submitting review

### ios upload_prepared

```sh
[bundle exec] fastlane ios upload_prepared
```

Upload an approved local archive and replace media without changing the existing review draft

### ios release

```sh
[bundle exec] fastlane ios release
```

Test, generate media, archive and submit App Review with manual release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
