.DEFAULT_GOAL := help
.PHONY: help apple-format apple-build apple-test apple-localizations

help:
	@echo "apple-format  Format Apple Swift sources"
	@echo "apple-build   Build the Apple app and embedded extensions for Simulator"
	@echo "apple-localizations  Check translation coverage and placeholders"
	@echo "apple-test    Run Apple unit tests (optional TEST_DESTINATION override)"

apple-format:
	swiftformat apple --swift-version 6

apple-build:
	xcodebuild -project apple/Muntathir.xcodeproj -scheme Muntathir -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

apple-localizations:
	python3 apple/scripts/check_localizations.py

apple-test: apple-localizations
	@set -eu; \
	destination="$${TEST_DESTINATION:-}"; \
	if [ -z "$$destination" ]; then \
		destinations=$$(xcodebuild -project apple/Muntathir.xcodeproj -scheme Muntathir -showdestinations); \
		simulator_id=$$(printf '%s\n' "$$destinations" | awk -F',' \
			'/platform:iOS Simulator,/ && /name:iPhone/ && !/error:/ { \
				for (i = 1; i <= NF; i++) if ($$i ~ /id:/) { \
					sub(/^.*id: */, "", $$i); print $$i; exit \
				} \
			}'); \
		if [ -z "$$simulator_id" ]; then \
			echo "No compatible iPhone simulator. Install an iOS runtime in Xcode or set TEST_DESTINATION." >&2; \
			exit 1; \
		fi; \
		destination="platform=iOS Simulator,id=$$simulator_id"; \
	fi; \
	xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
		-destination "$$destination" -only-testing:MuntathirTests
