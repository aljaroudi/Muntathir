# Asset packs

Only Quran Arabic and English stay bundled in the app and daily-ayah widget. Hadith uses `hadith`, containing `Hadith/hadith.db`. The on-demand `quran-translations` pack contains all twelve other translations.

Quran installs validated databases into the shared App Group, then removes the managed pack. Settings → Downloads deletes individual Quran languages, all downloaded translations, or the Hadith library. Restoring a deleted Quran language downloads the full pack, but restores only that language. Arabic and English cannot be removed. Missing translations leave Arabic readable and never trigger an automatic download.

An atomic index records pending installation and pack cleanup. Interrupted installs resume from local assets; failed cleanup retries on launch without restoring deleted languages. Installation needs temporary space for both the archive contents and installed copies. Downloaded Quran files are excluded from backup.

## Local testing — Xcode 27+

From the repository root:

```sh
uv run build/hadith/build.py --sittah --four
python3 apple/AssetPacks/assets.py package apple/build/AssetPacks/archives --content all
```

The shared **Muntathir** scheme already sets **Run → Options → Background Asset Packs** to `build/AssetPacks/archives`. Run from Xcode, open Hadith, and tap **Download Hadith**. Keep the debug session connected until installation finishes.

The folder contains packaged `.aar` files and is ignored by Git. Repackage and restart the debug session after database changes. No separate server, certificates, or manual URL override are needed for this workflow. See [Apple’s Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

If a device’s local-test installation gets stuck waiting for an app-install event, send that event, then rerun from Xcode:

```sh
xcrun backgroundassets-debug --list-devices
xcrun backgroundassets-debug --simulate --app-install --app-bundle-id com.aljaroudi.Muntathir --device-id <device-id>
```

Check that progress survives leaving and reopening Hadith. After installation, test offline reading, relaunch, **Settings → Downloads**, and redownload. Test interruption and retry as well.

## Database and size

The Six Books/Four Books build contains 61,799 narrations: **223.1 MiB installed**, with an **88.84 MiB local asset archive**. Apple’s processed download size remains unverified.

Schema v6 and application ID `1230262606` identify compatible reader databases. `--experimental-morphology` is off by default; production packaging rejects experimental databases. Packaging regenerates `AssetDownloadSizes.json` from actual archive byte counts. Both downloads use native, rounded size formatting; installed sizes come from local files.

## Before release

```sh
python3 apple/AssetPacks/assets.py validate --content all
python3 apple/AssetPacks/assets.py validate --content quran
python3 apple/AssetPacks/assets.py check-bundle /path/to/Muntathir.app
```

Register the downloader extension and shared app group for signing. Validate hosted delivery through TestFlight and record Apple’s processed download size before release. Keep the pack ID stable for compatible updates; coordinate breaking schemas with an app-compatible rollout.

Local packaging and the Run scheme do not upload, publish, or bundle Hadith. Production delivery must be verified in TestFlight for both packs before release.
