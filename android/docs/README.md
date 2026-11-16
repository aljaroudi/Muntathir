# Android port — handoff

Native Kotlin + Jetpack Compose version of the iOS app in [`apple/`](../../apple/). It keeps the same behavior with an Android-native design. These docs are the source of truth across sessions.

| Doc | Purpose |
|---|---|
| [TASKS.md](TASKS.md) | Phased checklist. **Start here every session.** |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, modules, data, conventions |
| [MAPPING.md](MAPPING.md) | iOS feature → Swift spec files → Android approach |

## Session workflow

1. Open `TASKS.md`, take the first unblocked `[ ]` task, and mark it `[~]`.
2. Read its Swift spec files in `MAPPING.md`. **The Swift code and READMEs define behavior**; these docs don't restate it.
3. Port the matching Swift tests first, then implement.
4. Run `just android-test`, mark the task `[x]`, and add a note only if something deviated.
5. Record new decisions below.

**Parallel agents:** only for tasks in different packages (e.g. P1 ports, P5 tools). One task ID per agent, each in its own git worktree. Merge one at a time and re-run tests.

## Decisions (2026-11-16)

- One platform per user: no iOS↔Android sync.
- **No login, no backend, no Firestore.** Same-OS continuity uses Android Auto Backup + device-to-device transfer. No live multi-device sync.
- No weather. Google Play only (Play Asset Delivery, no fallback). Wear OS later.
- minSdk 26. Avoid version-gated features.
- Smart search uses the existing `/v1/search` API. No new backend.
- Adhan: the Kotlin port of the same library.
- Simple, modern, minimal code. Three module types only.
