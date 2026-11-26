# Muntathir · منتظِر

Prayer times, Hijri calendar, daily Quran verses, and Qibla, localized into 15 languages.

## Repository

- [`apple/`](apple/README.md): iPhone/iPad app, Apple Watch, widgets, and tests.
- [`android/`](android/docs/README.md): Kotlin + Jetpack Compose port (in progress).
- [`web/`](web/README.md): Astro landing page.
- [`backend/`](backend/README.md): semantic search service.
- [`telegram/`](telegram/README.md): Telegram bot and Mini App.
- [`shared/fixtures/`](shared/fixtures/): test fixtures for both platforms.
- [`shared/figures/`](shared/figures/): religious-figure dataset.

## Commands

Install [just](https://github.com/casey/just) (`brew install just`) and run `just` from the repository root to list recipes. Common ones:

```sh
just apple-build
just apple-test
just web-dev
just backend-start
just data-build --dry-run
just version 1.2.0
just lane ios beta    # Fastlane lanes take key:value args
```

For release setup, see [fastlane/SETUP.md](fastlane/SETUP.md).

## Git hooks

```sh
brew install swiftformat
git config core.hooksPath .githooks
cd web && bun install --frozen-lockfile
```

- **Pre-commit** runs SwiftFormat on `apple/` and blocks the commit if anything changed (it never stages for you). It also runs web format and lint checks.
- **Pre-push** runs `just apple-test`, then web type checks, the production build, and build-output tests. Set `TEST_DESTINATION` to choose the simulator.
