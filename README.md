# Muntathir · منتظِر

Prayer times, Hijri calendar, daily Quran verses, and Qibla with Arabic and English localization.

## Repository

- [`apple/`](apple/): native iPhone/iPad app, Apple Watch companion, widgets, shared resources, and tests.
- Web and Android are planned; their projects will live in `web/` and `android/` when added.

See [Apple setup and release checks](apple/README.md).

## Commands

Run from repository root. `make` lists available commands.

```sh
make apple-format
make apple-build
make apple-test
TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' make apple-test
```

## Git hooks

Install SwiftFormat (`brew install swiftformat`), then enable tracked hooks in each clone:

```sh
git config core.hooksPath .githooks
```

Pre-commit formats only `apple/` using Swift 6. It blocks if tracked Apple Swift files differ from the index afterward. Review and stage changes before retrying; the hook never stages automatically.

Pre-push runs [Apple unit/integration tests](apple/MuntathirTests/) through `make apple-test`. It blocks on failed tests, missing Xcode, or an unavailable compatible simulator. Install an iOS simulator runtime through Xcode. Set `TEST_DESTINATION` to override simulator selection, including with `git push`. [UI tests](apple/MuntathirUITests/) remain manual.
