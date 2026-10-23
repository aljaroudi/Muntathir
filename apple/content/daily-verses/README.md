# Daily verse schedule

Edit `schedule.csv`: `hijriMonth,hijriDay,verseID`.

`verseID` is the integer primary key named `index` in the `quran` table of `apple/Muntathir/Resources/Quran/quran.db`. It is not the surah number or the verse number within a surah. Every file in that folder has the same 6,236 `index` values: `quran.db` holds Arabic, and each `<translation id>.db` (for example `en.qarai.db`, Ali Quli Qara’i’s English) holds one translation. Only Arabic is bundled in the app and widget. Translations are downloaded as [Apple-hosted asset packs](../../AssetPacks/) and opened read-only.

The first three assignments are **examples, not an approved schedule**. Replace them as needed, then fill every remaining ID. All 360 slots are required: months 1–12, days 1–30. Day 30 is skipped naturally when a corrected month has 29 days. IDs may repeat. Assignments repeat each Hijri year and honor manual and confirmed month corrections.

Find an ID from a surah and verse number, for example 20:25:

```sh
sqlite3 apple/Muntathir/Resources/Quran/quran.db 'SELECT "index", sura, aya FROM quran WHERE sura = 20 AND aya = 25;'
```

The CSV stays outside app resources. Until a complete generated `quran-daily.json` is bundled, the existing 32-verse sequence remains active through `quran-daily-ids.json`. The dated selector has no random or modulo fallback. An invalid bundled schedule shows verse unavailable rather than selecting unrelated content.

After filling the schedule, run from repository root:

```sh
python3 apple/scripts/import_daily_verses.py \
  --schedule apple/content/daily-verses/schedule.csv \
  --database apple/Muntathir/Resources/Quran/quran.db \
  --output apple/Muntathir/Resources/quran-daily.json
```

The importer validates all 360 unique dates and resolves every ID against the database, requiring nonempty Arabic and English text, before replacing output. Generated JSON contains only month, day, and verse ID numbers. The app and widget automatically bundle the same generated file. Runtime lookup uses the corrected Hijri month/day and changes at midnight in the selected location’s time zone.

English translation credit: **Ali Quli Qara’i**, also shown in Settings → Sources and licenses.

Run importer checks with `python3 -m unittest discover -s apple/scripts -p 'test_*.py'`.

The Quran reader loads the selected installed translation from `QuranTranslation.catalog`.
Each file carries its own search indexes, built from normalized text: `quran_words` (ranked
whole words and prefixes, plus Arabic roots in `quran.db` and English stemming in `en.*`),
`quran_words_vocab` (typo suggestions), and `quran_fts` (trigram, for text inside words).
Chinese files have no index and are searched with `LIKE`. Displayed text always comes from
the unchanged `quran` table. The reader, daily ayah, sharing, and medium widget use the same translation selection.
