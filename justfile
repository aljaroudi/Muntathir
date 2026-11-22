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

# Validate and package already-built DBs as Apple Background Asset Packs (rebuild data first with `just data-build --assets-only`)
[positional-arguments]
apple-packs content="all":
    python3 apple/AssetPacks/assets.py package --content "$1"

# Validate content databases for both platforms
[positional-arguments]
packs-check content="all":
    python3 apple/AssetPacks/assets.py validate --content "$1"

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

[positional-arguments]
[arg("platform", help="ios or android")]
[arg("args", help="Fastlane key:value options")]
[doc("Run a Fastlane lane from the repository root")]
lane platform name *args:
    LC_ALL="${LC_ALL:-en_US.UTF-8}" LANG="${LANG:-en_US.UTF-8}" PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:${PATH:-}" BUNDLE_PATH="${BUNDLE_PATH:-vendor/bundle}" bundle exec fastlane "$@"

[positional-arguments]
[doc("Set the release version for Apple and Android (X.Y.Z)")]
version number:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Expected a release version in X.Y.Z format." >&2
        exit 2
    fi
    temp=$(mktemp Version.xcconfig.XXXXXX)
    trap 'rm -f "$temp"' EXIT
    printf 'MARKETING_VERSION = %s\n' "$1" > "$temp"
    mv "$temp" Version.xcconfig

# Android Gradle; JAVA_HOME defaults to Android Studio's bundled JDK
android_gradle := 'cd android && JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}" ./gradlew'

# Regenerate Android strings from the Apple catalogs
android-strings:
    python3 android/scripts/strings.py

# Build the Android debug app and its Wear OS app
android-build:
    {{ android_gradle }} :app:assembleDebug :wear:assembleDebug

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

# Validate and stage already-built DBs as Google Play Asset Delivery packs (rebuild data first with `just data-build --assets-only`)
[positional-arguments]
android-packs content="all":
    python3 apple/AssetPacks/assets.py android --content "$1"

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

[doc("Check and restart the search API on the hosting Mac")]
backend-deploy: backend-check backend-test
    launchctl kickstart -k "gui/$(id -u)/com.muntathir.search"

# Clone the content databases for local Telegram development and tests
telegram-data:
    cd telegram && bun scripts/data.ts

[doc("Typecheck, build and test the Telegram bot and Mini App")]
telegram-check:
    cd telegram && bun run check && bun run scripts/build.ts && bun test

[positional-arguments]
[arg("args", help="--build-only | --rollback")]
[doc("Release the committed Telegram bot on the hosting Mac")]
telegram-release *args:
    cd telegram && bun scripts/release.ts "$@"

[positional-arguments]
[arg("args", help="--tunnel | --agents | --apply")]
[doc("Provision the Telegram tunnel and launch agents (dry run without --apply)")]
telegram-install *args:
    cd telegram && bun scripts/install.ts "$@"

[positional-arguments]
[arg("args", help="--apply")]
[doc("Show the bot's settings, or apply commands and menu with --apply")]
telegram-configure *args:
    cd telegram && bun scripts/configure.ts "$@"

[arg("args", help="flags for build/build.py: --dry-run | --assets-only | --max-budget USD")]
[doc("Rebuild reader databases, package assets, and refresh search")]
data-build *args:
    python3 build/build.py {{ args }}

[doc("Format Apple Swift and web sources (apple-format + web-format)")]
format: apple-format web-format

[doc("Run Apple unit tests and web output tests (apple-test + web-test)")]
test: apple-test web-test

[doc("Format platforms with staged changes, then check and lint web sources")]
pre-commit:
    #!/usr/bin/env sh
    set -eu
    format_staged_platform() {
        platform="$1"
        shift
        staged=$(git diff --cached --name-only -- "$platform/")
        [ -n "$staged" ] || return 0
        # Formatters operate on the working tree, while the commit uses the index.
        if ! git diff --quiet -- "$@"; then
            echo "Stage or stash unstaged $platform source changes before formatting." >&2
            exit 1
        fi
        just "$platform-format"
        if ! git diff --quiet -- "$@"; then
            echo "Review and stage the formatted $platform files, then commit again." >&2
            exit 1
        fi
    }
    format_staged_platform apple ':(glob)apple/**/*.swift'
    format_staged_platform android ':(glob)android/**/*.kt' ':(glob)android/**/*.kts'
    just web-check web-lint

[doc("Same checks as .githooks/pre-push: apple-test + web-check + web-build + web-test")]
pre-push: apple-test web-check web-build web-test

# Generate the English GitHub changelog from the shared release notes
changelog:
    python3 shared/scripts/generate-changelog.py
