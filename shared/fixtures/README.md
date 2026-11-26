# Shared test fixtures

Reference data for both platforms. Apple tests bundle identical copies in [`apple/MuntathirTests/Fixtures/`](../../apple/MuntathirTests/Fixtures/); keep them identical. Android `core` tests read this folder directly.

- `corrections-v1.json`: version-one calendar feed wire shape. Fixture-only; never real announcements.
- `lexicon-normalize.json`: Arabic spelling folds from `shared/lexicon/normalize.py` that the dictionary readers must reproduce. Regenerate it from that module after changing it.
- `lexicon-gold.json`: hand-checked word roots; `shared/lexicon/evaluate.py` fails when the dictionary lookup gets one wrong. `optional` marks particles, where no root is also right.
- Prayer times: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); source and tolerance remain in each JSON.
