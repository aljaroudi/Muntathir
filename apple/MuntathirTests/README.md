# Unit and integration tests

From repository root, run `make apple-test`. It selects the first compatible iPhone simulator and runs only `MuntathirTests`.

Override selection with `TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' make apple-test`. Xcode and a compatible iOS runtime are required. The pre-push hook runs this same Makefile target.

Swift Testing covers calendar boundaries, overrides, content integrity, prayer fixtures/high latitudes, notification planning, preferences, device-location restoration, feed caching/worldwide source selection, widgets, Watch settings, and ayah rendering.

`Fixtures/` is copied into the test bundle; maintain parity with [Shared fixtures](../Shared/Fixtures/). Feed tests inject simulated HTTP responses, not a deployed server. Hardware behavior requires [device checks](../README.md#release-checks).

`make apple-localizations` checks all interface strings, placeholder parity, observance translations, and location-purpose strings in the 15 supported locales. `make apple-test` runs this check before simulator tests.
