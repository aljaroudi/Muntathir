# Unit and integration tests

```sh
just apple-test
TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' just apple-test
```

These commands run `MuntathirTests` (Swift Testing) on the first compatible iPhone simulator, after `just apple-localizations` checks strings in all 15 locales. The pre-push hook runs the same recipe.

`Fixtures/` must stay identical to [shared fixtures](../../shared/fixtures/). Feed tests use simulated HTTP responses, so hardware behavior still needs the [device checks](../README.md#release-checks).
