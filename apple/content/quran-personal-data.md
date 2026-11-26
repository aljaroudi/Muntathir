# Highlights, bookmarks, and sharing

Quran text and translations stay in the bundled read-only SQLite database. Personal data is a SwiftData store, `ReadingHighlights` (`HighlightRecord`, `BookmarkRecord`), synced through the private CloudKit database `iCloud.com.aljaroudi.Muntathir`. See `Persistence/QuranUserStore.swift` and `QuranUserSchema.swift`.

## Records and conflicts

- Each installation writes its own record per highlight or bookmark. The installation ID lives in `QuranIdentity`, excluded from device backups, so a restored device doesn't write the same records.
- The winner for an item is the newest `modifiedAt`, ties broken by `recordID`. Deleting writes a tombstone (`isTombstone`) with a new timestamp rather than removing the record, so stale offline values can't reappear. Device clock skew can affect ordering of simultaneous offline edits.
- CloudKit production schema changes must stay compatible with older clients.

## Store behavior

- The main-actor store saves explicitly and rolls back failed saves. Editors keep unsaved text outside SwiftData.
- A store-open failure never deletes data or substitutes an in-memory store. Reading and sharing stay available, and saved lists offer a retry.
- Managed models never cross actors.
- Copy and image sharing include the Arabic, the displayed translation and attribution, and the reference. Personal notes are never included.

## Tests

- Unit tests and previews use an in-memory configuration with CloudKit disabled.
- UI tests use a separate disk store (`HighlightsUITests`), reset only by `--ui-testing`; `--ui-testing-preserve-state` keeps it across relaunches. `--ui-testing-quran-save-failure` injects a failed save to check the draft survives.

## CloudKit release checks

Entitlements include CloudKit, the container and push; background modes include remote notifications. Sync isn't immediate: offline edits save locally and sync when CloudKit is available.

1. Verify the signed app's provisioning profile includes the container and push.
2. On two devices with the same iCloud account (development build): add highlights, notes and bookmarks, edit different items offline, reconnect, and check both directions converge. Repeat with deletions. Check relaunch, account unavailability and interrupted sync.
3. Inspect the development CloudKit schema in CloudKit Console or with `cktool export-schema` (needs a management token). Saving a test annotation in the development app creates the record types.
4. Deploy the verified schema to production in CloudKit Console before shipping, then validate a TestFlight build against production. Never reset production data.

Two-device sync and production schema deployment haven't been verified yet.
