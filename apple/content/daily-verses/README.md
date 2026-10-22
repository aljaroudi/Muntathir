# Daily verse schedule

Edit `schedule.csv`: `hijriMonth,hijriDay,verseID`.

`verseID` is the integer primary key named `index` in the root `db.db` Quran table. It is not the surah number or the verse number within a surah. The database contains 6,236 verses, with Arabic in `text` and Ali Quli Qara’i’s English translation in `en_qarai`. The original database is bundled unchanged in the app and widget; neither writes to it or fetches verse text over the network.

The first three assignments are **examples, not an approved schedule**. Replace them as needed, then fill every remaining ID. All 360 slots are required: months 1–12, days 1–30. Day 30 is skipped naturally when a corrected month has 29 days. IDs may repeat. Assignments repeat each Hijri year and honor manual and confirmed month corrections.

Find an ID from a surah and verse number, for example 20:25:

```sh
sqlite3 db.db 'SELECT "index", sura, aya FROM quran WHERE sura = 20 AND aya = 25;'
```

The CSV stays outside app resources. Until a complete generated `quran-daily.json` is bundled, the existing 31-verse sequence remains active through `quran-daily-ids.json`. The dated selector has no random or modulo fallback. An invalid bundled schedule shows verse unavailable rather than selecting unrelated content.

After filling the schedule, run from repository root:

```sh
python3 apple/scripts/import_daily_verses.py \
  --schedule apple/content/daily-verses/schedule.csv \
  --database db.db \
  --output apple/Muntathir/Resources/quran-daily.json
```

The importer validates all 360 unique dates and resolves every ID against the database, requiring nonempty Arabic and English text, before replacing output. Generated JSON contains only month, day, and verse ID numbers. The app and widget automatically bundle the same generated file. Runtime lookup uses the corrected Hijri month/day and changes at midnight in the selected location’s time zone.

English translation credit: **Ali Quli Qara’i**, also shown in Settings → Sources and licenses.

Run importer checks with `python3 -m unittest discover -s apple/scripts -p 'test_*.py'`.

The Quran reader loads available translation columns through `QuranTranslation.catalog`.
When adding a translation, add its catalog entry and include its column in `quran_fts`.
Arabic search uses a disposable, normalized in-memory index; displayed text always comes
from the unchanged database. Reader translation selection does not affect widgets.
