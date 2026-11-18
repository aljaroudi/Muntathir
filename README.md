# Muntathir · منتظِر

Prayer times, Hijri calendar, daily Quran verses, and Qibla with localization in Arabic, English, French, German, Indonesian, Italian, Japanese, Malay, Persian, Russian, Spanish, Turkish, Urdu, and Simplified/Traditional Chinese.

## Repository

- [`apple/`](apple/): native iPhone/iPad app, Apple Watch companion, widgets, shared resources, and tests.
- [`web/`](web/README.md): bilingual Astro landing page, built with Bun, Tailwind CSS, and Vite+.
- [`android/`](android/docs/README.md): Kotlin + Jetpack Compose port in progress; see its handoff docs.
- [`shared/fixtures/`](shared/fixtures/): test fixtures used by both platforms.
- [`shared/figures/`](shared/figures/): religious-figure data format, family relationships, names, and uncertain historical dates.
- [`backend/`](backend/README.md): Qdrant/Gemini semantic search, corpus batches, evaluation, and local deployment.

See [Apple setup and release checks](apple/README.md).

## Commands

Install [just](https://github.com/casey/just) (`brew install just`), then run from repository root. `just` lists available commands.

```sh
just apple-format
just apple-build
just apple-test
TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' just apple-test
just lane ios marketing
just lane ios web_media
just lane ios screenshots languages:ar,en workers:2
just lane android internal aab:/absolute/path/app-release.aab
just version 1.2.0
just web-dev
just web-validate
just backend-start
just data-build --dry-run
```

Run `just lane <platform> <lane>` from the repository root using Fastlane’s `key:value` syntax. See [release setup](fastlane/SETUP.md). Update the shared release version with `just version X.Y.Z`.


## Git hooks

Install SwiftFormat (`brew install swiftformat`) and just (`brew install just`), then enable tracked hooks in each clone:

```sh
git config core.hooksPath .githooks
```

Pre-commit formats only `apple/` using Swift 6. It blocks if tracked Apple Swift files differ from the index afterward. Review and stage changes before retrying; the hook never stages automatically.

Pre-push runs [Apple unit/integration tests](apple/MuntathirTests/) through `just apple-test`. It blocks on failed tests, missing Xcode, or an unavailable compatible simulator. Install an iOS simulator runtime through Xcode. Set `TEST_DESTINATION` to override simulator selection, including with `git push`. [UI tests](apple/MuntathirUITests/) remain manual.

Web hooks also require Bun and installed dependencies (`cd web && bun install --frozen-lockfile`). Pre-commit checks web formatting and lint. Pre-push runs web type checks, a production build, and build-output tests after Apple tests. See [web setup and Vercel deployment](web/README.md).
