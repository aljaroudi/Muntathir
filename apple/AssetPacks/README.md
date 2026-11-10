# Asset packs

Only Quran Arabic and English stay bundled in the app and daily-ayah widget. Hadith uses `hadith`, containing `Hadith/hadith.db`. Supplications use the independent `supplications` pack, containing `Supplications/supplications.db`. The on-demand `quran-translations` pack contains all twelve other translations.

Quran installs validated databases into the shared App Group, then removes the managed pack. Settings → Downloads deletes individual Quran languages, all downloaded translations, the Hadith library, or supplications independently. Restoring a deleted Quran language downloads the full pack, but restores only that language. Arabic and English cannot be removed. Missing translations leave Arabic readable and never trigger an automatic download.

An atomic index records pending installation and pack cleanup. Interrupted installs resume from local assets; failed cleanup retries on launch without restoring deleted languages. Installation needs temporary space for both the archive contents and installed copies. Downloaded Quran files are excluded from backup.

## Local testing — Xcode 27+

From the repository root:

```sh
uv run build/hadith/build.py --sittah --four
python3 apple/AssetPacks/assets.py package --content all
```

The shared **Muntathir** scheme already sets **Run → Options → Background Asset Packs** to `build/AssetPacks/archives`. Run from Xcode, open Hadith, and tap **Download Hadith**. Keep the debug session connected until installation finishes.

The packaging command defaults to the same `apple/build/AssetPacks/archives` folder used by the Run scheme and release upload lane. An explicit output path overrides that default.

The folder contains packaged `.aar` files and is ignored by Git. Repackage and restart the debug session after database changes. No separate server, certificates, or manual URL override are needed for this workflow. See [Apple’s Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

`--four` includes the Four Books, Nahj al-Balagha, al-Sahifa al-Sajjadiyya, Wasa’il al-Shia, and Bihar al-Anwar. The last three are curated additions, not members of the Four Books. Al-Istibsar supplies all four volumes; al-Sahifa supplies its Arabic introduction and 54 prayers in the separate `supplications.db` output. The OpenITI additions use the pinned OpenITI 2025-01-09 files under `build/library/data/OpenITI_data_2025-1-9`. Their checksums and provenance are recorded in `build/hadith/data/openiti-editions.json`; changed editions require boundary review before import. Reading entries retain author commentary and are not a canonical hadith count. Wasa’il contains 30 volumes. Bihar contains 106 supplied volumes; 103 and 108–110 are missing. See [adding and classifying books](../../build/library/README.md).

Reviewed Arabic chapter mappings live in `build/hadith/data/arabic-chapters.json`. They preserve existing English titles and verify the original narration URLs and text before filling blank Arabic titles. Original headings come from Arabic source indexes; modern summaries without original headings use numbered Arabic section labels. Every build writes a sibling `.chapter-gaps.csv` report. To audit the entire library, build without `--sittah --four`, using `--output` to keep the app's selected database intact.

If a device’s local-test installation gets stuck waiting for an app-install event, send that event, then rerun from Xcode:

```sh
xcrun backgroundassets-debug --list-devices
xcrun backgroundassets-debug --simulate --app-install --app-bundle-id com.aljaroudi.Muntathir --device-id <device-id>
```

Check that progress survives leaving and reopening Hadith. After installation, test offline reading, relaunch, **Settings → Downloads**, and redownload. Test interruption and retry as well.

## Database and size

The selected Hadith library contains 145,479 reading entries and 9 separate introductions. Unnumbered chapters, commentary, and appendices remain reading entries; only explicitly titled prefaces are separated as introductions. The separate supplications asset contains an introduction and 54 prayers. Installed and archive sizes are generated locally; Apple’s processed download sizes remain unverified.

Schema v7 and application ID `1230262606` identify compatible reader databases. `--experimental-morphology` is off by default; production packaging rejects experimental databases. Packaging regenerates `AssetDownloadSizes.json` from actual archive byte counts. All downloads use native, rounded size formatting; installed sizes come from local files.

## Before release

```sh
python3 apple/AssetPacks/assets.py validate --content all
python3 apple/AssetPacks/assets.py validate --content quran
python3 apple/AssetPacks/assets.py check-bundle /path/to/Muntathir.app
```

Register the downloader extension and shared app group for signing. Validate hosted delivery through TestFlight and record Apple’s processed download size before release. Keep the pack ID stable for compatible updates; coordinate breaking schemas with an app-compatible rollout.

Local packaging and the Run scheme do not upload, publish, or bundle Hadith. Production delivery must be verified in TestFlight for both packs before release.
