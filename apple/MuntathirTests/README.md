# Unit and integration tests

From repository root, run `make apple-test`. It selects the first compatible iPhone simulator and runs only `MuntathirTests`.

Override selection with `TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' make apple-test`. Xcode and a compatible iOS runtime are required. The pre-push hook runs this same Makefile target.

Swift Testing covers calendar boundaries, overrides, content integrity, prayer fixtures/high latitudes, notification planning, preferences, device-location restoration, feed caching/coverage, widgets, Watch settings, ayah rendering, and the counter state machine.

`Fixtures/` is copied into the test bundle; maintain parity with [Shared fixtures](../Shared/Fixtures/). Feed tests inject simulated HTTP responses, not a deployed server. Hardware behavior requires [device checks](../README.md#release-checks).
