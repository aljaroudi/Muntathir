# Shared test fixtures

Reference data for both platforms. Apple tests bundle identical copies in [`apple/MuntathirTests/Fixtures/`](../../apple/MuntathirTests/Fixtures/); keep them identical. Android `core` tests read this folder directly.

- `corrections-v1.json`: version-one calendar feed wire shape. Fixture-only; never real announcements.
- Prayer times: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); source and tolerance remain in each JSON.
