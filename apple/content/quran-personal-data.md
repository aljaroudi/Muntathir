# Quran favorites, notes, and sharing

Quran text and translations remain in the bundled read-only SQLite database.
Personal data uses a separate SwiftData store named `QuranPersonal`, configured
for the private CloudKit database in `iCloud.com.aljaroudi.Muntathir`.

## Schema and updates

`QuranUserSchemaV1` is the released schema. Keep it immutable. Future persisted
changes need a new `VersionedSchema`, an entry in `QuranUserMigrationPlan`, and
an appropriate migration stage. Do not add a fictional migration for V1.
The disk-backed V1 fixture test creates data with the frozen V1 schema and
reopens it through the current migration plan; extend it as schemas evolve.
CloudKit production schema changes must remain compatible with older clients.

Each installation writes its own record for a verse. The installation ID lives
in a directory excluded from device backups, so restored devices do not write
the same record. Favorite and note values have independent timestamps. Resolve
each field by newest timestamp, breaking ties by record ID. Clearing a note or
unfavoriting writes an empty state with a new timestamp; it does not delete the
record. These timestamps prevent stale offline values from reappearing.
Device clock differences can influence simultaneous offline conflict ordering.
There is one visible note per verse and no note revision history UI.

The main-actor store explicitly saves changes and rolls back failed saves.
Editors retain unsaved text outside SwiftData. Store-open failures never delete
data or silently substitute an in-memory store. Reading and sharing remain
available, and the saved lists provide a retry action.
SwiftUI observes imports with `@Query`; managed models never cross actors.

Copy and image sharing include Arabic, the displayed translation and attribution,
and the surah/verse reference. Personal notes are never included.

## Tests

Unit tests and previews must use an isolated configuration with CloudKit disabled.
UI tests use a separate disk store, reset only by the explicit `--ui-testing`
launch mode. `--ui-testing-preserve-state` preserves that store across relaunches.
The save-failure UI test injects a failed save and verifies the draft remains.

## CloudKit release checks

The app entitlements include CloudKit, `iCloud.com.aljaroudi.Muntathir`, and push;
background modes include remote notifications. Existing iCloud key-value
preferences remain separate. Offline edits save locally and synchronize when
CloudKit is available; sync is not immediate.

1. Verify the signed app's provisioning profile includes this container and push.
2. Run a development-signed build on two devices signed into the same iCloud
   account. Add a favorite and note, edit different fields offline, reconnect,
   and verify convergence in both directions. Repeat with note deletion and
   unfavoriting. Verify relaunch, account unavailability, and interrupted sync.
3. Inspect the development CloudKit schema in CloudKit Console or with an
   authorized `cktool export-schema` command. Launching the development app and
   saving a test annotation initializes the model's record types.
4. Deploy the verified schema to production in CloudKit Console before shipping.
   Validate a TestFlight build against production. Never reset production data.

Implementation validation on 2026-10-22: the signed device build succeeded and
its embedded profile includes the container and development push entitlement.
Development schema inspection could not run because no CloudKit management
token was configured. Only one physical device was connected, so two-device
sync and production schema deployment remain release checks.
