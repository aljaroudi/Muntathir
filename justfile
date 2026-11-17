set shell := ["sh", "-eu", "-c"]

# Show available commands
default:
    @just --list

# Format Apple Swift sources
apple-format:
    swiftformat apple --swift-version 6

# Build the Apple app and embedded extensions for Simulator
apple-build:
    xcodebuild -project apple/Muntathir.xcodeproj -scheme Muntathir -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Check translation coverage and placeholders
apple-localizations:
    python3 apple/scripts/check_localizations.py

[doc("Run Apple unit tests after localizations; set TEST_DESTINATION to override simulator")]
apple-test: apple-localizations
    #!/usr/bin/env sh
    set -eu
    destination="${TEST_DESTINATION:-}"
    if [ -z "$destination" ]; then
        destinations=$(xcodebuild -project apple/Muntathir.xcodeproj -scheme Muntathir -showdestinations)
        simulator_id=$(printf '%s\n' "$destinations" | awk -F',' \
            '/platform:iOS Simulator,/ && /name:iPhone/ && !/error:/ { \
                for (i = 1; i <= NF; i++) if ($i ~ /id:/) { \
                    sub(/^.*id: */, "", $i); print $i; exit \
                } \
            }')
        if [ -z "$simulator_id" ]; then
            echo "No compatible iPhone simulator. Install an iOS runtime in Xcode or set TEST_DESTINATION." >&2
            exit 1
        fi
        destination="platform=iOS Simulator,id=$simulator_id"
    fi
    xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
        -destination "$destination" -only-testing:MuntathirTests

[arg("args", help="Fastlane lane + key:value options: check | tests | cleanup | screenshots languages:ar,en workers:2 | style | previews | watch_screenshots | web_media | marketing | testflight_public | app_store")]
[doc("Run a Fastlane lane from apple/ (Homebrew Ruby + vendor/bundle; see apple/fastlane/SETUP.md)")]
apple-lane *args:
    #!/usr/bin/env sh
    set -eu
    export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:${PATH:-}"
    export BUNDLE_PATH=vendor/bundle
    cd apple
    bundle exec fastlane {{ args }}

[arg("args", help="languages=ar,en workers=2 → apple/build/marketing/raw/ (default workers 2)")]
[doc("Capture raw Apple screenshots into apple/build/marketing/raw")]
apple-screenshots *args:
    #!/usr/bin/env sh
    set -eu
    languages=""
    workers=""
    set -- {{ args }}
    for argument in "$@"; do
        case "$argument" in
            languages=*) languages=${argument#languages=} ;;
            workers=*) workers=${argument#workers=} ;;
            *) echo "Unknown option: $argument (use languages=ar,en workers=2)" >&2; exit 2 ;;
        esac
    done
    set -- screenshots
    [ -n "$languages" ] && set -- "$@" "languages:$languages"
    [ -n "$workers" ] && set -- "$@" "workers:$workers"
    just apple-lane "$@"

[arg("args", help="languages=ar,en → apple/build/marketing/store/")]
[doc("Style raw screenshots into apple/build/marketing/store")]
apple-style *args:
    #!/usr/bin/env sh
    set -eu
    languages=""
    set -- {{ args }}
    for argument in "$@"; do
        case "$argument" in
            languages=*) languages=${argument#languages=} ;;
            *) echo "Unknown option: $argument (use languages=ar,en)" >&2; exit 2 ;;
        esac
    done
    set -- style
    [ -n "$languages" ] && set -- "$@" "languages:$languages"
    just apple-lane "$@"

# Android Gradle; JAVA_HOME defaults to Android Studio's bundled JDK
android_gradle := 'cd android && JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}" ./gradlew'

# Regenerate Android strings from the Apple catalogs
android-strings:
    python3 android/scripts/strings.py

# Build the Android debug app
android-build:
    {{ android_gradle }} :app:assembleDebug

[doc("Check Android strings and run core + app unit and screenshot tests")]
android-test:
    python3 android/scripts/strings.py --check
    {{ android_gradle }} test testDebugScreenshotTestDefaultTestSuite

# Record Android screenshot references after reviewing the diffs
android-screenshots:
    {{ android_gradle }} updateDebugScreenshotTestDefaultTestSuite

# Format Android Kotlin sources (ktlint via Spotless)
android-format:
    {{ android_gradle }} spotlessApply

# Validate content databases (same checks as iOS) and copy them into the Play asset-pack modules
android-packs:
    python3 apple/AssetPacks/assets.py android --content hadith
    python3 apple/AssetPacks/assets.py android --content supplications
    python3 apple/AssetPacks/assets.py android --content quran

# Install the debug bundle with local Play Asset Delivery testing; set ANDROID_SERIAL to choose a device
android-local-testing: android-packs
    #!/usr/bin/env bash
    set -euo pipefail
    sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    # Maven's bundletool doesn't embed aapt2; use the newest SDK build-tools.
    aapt2="$(ls -d "$sdk"/build-tools/*/ | sort -V | tail -1)aapt2"
    ({{ android_gradle }} :app:bundleDebug)
    ({{ android_gradle }} bundletool --args="build-apks --local-testing --overwrite --aapt2=$aapt2 --bundle=app/build/outputs/bundle/debug/app-debug.aab --output=build/local-testing.apks")
    ({{ android_gradle }} bundletool --args="install-apks --apks=build/local-testing.apks --adb=$sdk/platform-tools/adb ${ANDROID_SERIAL:+--device-id=$ANDROID_SERIAL}")

[arg("args", help="astro/bun flags after dev, e.g. -- --background")]
[doc("Run the Astro landing page (web/); uses bun run dev")]
web-dev *args:
    cd web && bun run dev {{ args }}

# Format web sources
web-format:
    cd web && bun run format

# Lint web sources
web-lint:
    cd web && bun run lint

[doc("Typecheck the landing page (astro check); not format/lint/build")]
web-check:
    cd web && bun run check

# Build the landing page
web-build:
    cd web && bun run build

[doc("Test built web output; run web-build first (or use web-validate)")]
web-test:
    cd web && bun test

[doc("Full web gate: format + lint + check + build + test")]
web-validate:
    cd web && bun run validate

[doc("Start the Bun search API in backend/api")]
backend-start:
    cd backend/api && bun run start

# Test the search API
backend-test:
    cd backend/api && bun test

# Typecheck the search API
backend-check:
    cd backend/api && bun run check

[arg("args", help="flags for build/build.py: --dry-run | --assets-only | --max-budget USD")]
[doc("Rebuild reader databases, package assets, and refresh search")]
data-build *args:
    python3 build/build.py {{ args }}

[doc("Format Apple Swift and web sources (apple-format + web-format)")]
format: apple-format web-format

[doc("Run Apple unit tests and web output tests (apple-test + web-test)")]
test: apple-test web-test

[doc("Same checks as .githooks/pre-commit: apple-format + web-check + web-lint")]
pre-commit: apple-format web-check web-lint

[doc("Same checks as .githooks/pre-push: apple-test + web-check + web-build + web-test")]
pre-push: apple-test web-check web-build web-test
