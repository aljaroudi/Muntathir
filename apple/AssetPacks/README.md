# Asset packs

The app bundles only Quran Arabic and English. Everything else is an Apple-hosted asset pack:

| Pack | Contents | Delivery |
| --- | --- | --- |
| `quran-translations` | The other 12 Quran translations | On demand |
| `hadith` | `Hadith/hadith.db` | On demand |
| `supplications` | `Supplications/supplications.db` | Essential (installed with the app) |
| `rulings-v2` | `Rulings/rulings.db` | On demand |

The app copies each validated pack into the shared App Group and reads only that copy, so iOS can't update it in place. Settings → Downloads removes content per language or library. Arabic and English can't be removed, and missing translations never trigger a download. Downloaded Quran files are excluded from backup.

## Build and test locally (Xcode 27+)

```sh
python3 build/build.py --assets-only   # build databases and package them
just apple-packs                       # package already-built databases
```

Archives go to `apple/build/AssetPacks/archives` (ignored by Git). The **Muntathir** scheme's Run → Options → Background Asset Packs already points there. Run from Xcode, open Hadith, and tap **Download Hadith**, keeping the debug session attached until installation finishes. Repackage and relaunch after any database change.

If a device's local install hangs waiting for an app-install event:

```sh
xcrun backgroundassets-debug --list-devices
xcrun backgroundassets-debug --simulate --app-install --app-bundle-id com.aljaroudi.Muntathir --device-id <device-id>
```

Then test that progress survives leaving Hadith, plus offline reading, relaunch, Settings → Downloads, redownload, and interruption/retry.

## Hadith build

`--four` adds the Four Books, Nahj al-Balagha, al-Sahifa al-Sajjadiyya, Wasa'il al-Shia, and Bihar al-Anwar. The Sahifa's 54 prayers and the Kumayl, Sabah, and Nudba supplications (from `build/hadith/data/supplications.json`) go into `supplications.db`. To add or classify books, see the [source library](../../build/library/README.md).

- Reviewed Arabic chapter titles live in `build/hadith/data/arabic-chapters.json`. Every build writes a `.chapter-gaps.csv` report.
- To audit the whole library, build without `--sittah --four` and pass `--output`, so the app's database stays untouched.
- New builds use schema v8 (basic word and phrase indexes only); the reader accepts v7 and v8. The application ID is `1230262606`.
- Production packaging rejects `--experimental-morphology` databases. Packaging also regenerates `AssetDownloadSizes.json` from archive sizes.

To shrink existing indexes without reimporting:

```sh
python3 build/hadith/compact.py build/hadith/dist/hadith.db build/hadith/dist/compact/hadith.db
bash build/quran/build.sh
```

Don't publish compact outputs over existing packs. v7-only builds reject v8 Hadith, and older Quran readers expect the removed trigram index. If old builds must keep working, use new pack IDs.

## Rulings

```sh
python3 build/rulings/scrape.py      # refresh all sources
python3 build/rulings/books.py       # books only
python3 build/rulings/treatise.py    # treatises only (official API)
python3 build/rulings/build.py       # → build/rulings/dist/rulings.db
just apple-packs rulings
bundle exec ruby fastlane/ios/asset_pack_delivery.rb --upload rulings
```

Upload from the repository root using the [Fastlane Ruby environment](../../fastlane/SETUP.md). Keep the crawl mirror at `build/rulings/data/fatwa.sqlite`, since existing connections depend on that path. The reader checks application ID `1179809601`, schema versions 1–2, integrity, and FTS. Questions are identified by authority, language, and source question ID.

## Release

```sh
just packs-check
just packs-check quran
python3 apple/AssetPacks/assets.py check-bundle /path/to/Muntathir.app
```

- Register the downloader extension and App Group for signing. Verify hosted delivery in TestFlight and record Apple's processed download size.
- To update a pack, upload the rebuilt archive, choose **Replace** in App Store Connect → Asset Packs, and submit it. Then verify in TestFlight with the old pack installed.
- Keep pack IDs stable for compatible updates. For a breaking schema, ship the app that reads the new schema first. Older apps skip packs that fail validation instead of breaking.

The app checks hosted versions on launch, on returning after 20 hours, and in the daily background refresh. It swaps in a new copy only after integrity, schema, and query checks pass. A version that fails is skipped until the next app update, and the rejection is logged under the `AssetPacks` category. Xcode-served packs all report version 0, so the app compares them by archive size instead.

See Apple's [asset pack submission guide](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-apple-hosted-asset-packs).
