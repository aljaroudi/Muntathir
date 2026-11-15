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

# Run Apple unit tests (optional TEST_DESTINATION override)
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

# Run the landing page (pass -- --background for background mode)
web-dev *args:
    cd web && bun run dev {{args}}

# Format web sources
web-format:
    cd web && bun run format

# Lint web sources
web-lint:
    cd web && bun run lint

# Typecheck the landing page
web-check:
    cd web && bun run check

# Build the landing page
web-build:
    cd web && bun run build

# Test built web output
web-test:
    cd web && bun test

# Format, lint, typecheck, build, and test the site
web-validate:
    cd web && bun run validate

# Run the search API
backend-start:
    cd backend/api && bun run start

# Test the search API
backend-test:
    cd backend/api && bun test

# Typecheck the search API
backend-check:
    cd backend/api && bun run check

# Rebuild reader databases and refresh search
data-build *args:
    python3 build/build.py {{args}}

# Format Apple and web sources
format: apple-format web-format

# Run Apple and web tests
test: apple-test web-test

# Checks run by the pre-commit hook
pre-commit: apple-format web-check web-lint

# Checks run by the pre-push hook
pre-push: apple-test web-check web-build web-test
