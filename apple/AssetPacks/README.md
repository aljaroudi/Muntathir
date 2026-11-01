# Asset packs

Quran Arabic and the shipping translations stay bundled in the app and daily-ayah widget. Hadith uses one on-demand pack, `hadith`, containing `Hadith/hadith.db`.

## Local testing — Xcode 27+

From the repository root:

```sh
uv run build/hadith/build.py --sittah --four
python3 apple/AssetPacks/assets.py package apple/build/AssetPacks/archives --content hadith
```

The shared **Muntathir** scheme already sets **Run → Options → Background Asset Packs** to `build/AssetPacks/archives`. Run from Xcode, open Hadith, and tap **Download Hadith**. Keep the debug session connected until installation finishes.

The folder contains packaged `.aar` files and is ignored by Git. Repackage and restart the debug session after database changes. No separate server, certificates, or manual URL override are needed for this workflow. See [Apple’s Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

If a device’s local-test installation gets stuck waiting for an app-install event, send that event, then rerun from Xcode:

```sh
xcrun backgroundassets-debug --list-devices
xcrun backgroundassets-debug --simulate --app-install --app-bundle-id com.aljaroudi.Muntathir --device-id <device-id>
```

Check that progress survives leaving and reopening Hadith. After installation, test offline reading, relaunch, **Remove Download**, and redownload. Test interruption and retry as well.

## Database and size

The Six Books/Four Books build contains 61,799 narrations: **223.1 MiB installed**, with an **88.84 MiB local asset archive**. Apple’s processed download size remains unverified.

Schema v6 and application ID `1230262606` identify compatible reader databases. `--experimental-morphology` is off by default; production packaging rejects experimental databases. Quran manifests remain available through `--content quran`, but Quran delivery is unchanged.

## Before release

```sh
python3 apple/AssetPacks/assets.py validate --content hadith
python3 apple/AssetPacks/assets.py validate --content quran
python3 apple/AssetPacks/assets.py check-bundle /path/to/Muntathir.app
```

Register the downloader extension and shared app group for signing. Validate hosted delivery through TestFlight and record Apple’s processed download size before release. Keep the pack ID stable for compatible updates; coordinate breaking schemas with an app-compatible rollout.

Local packaging and the Run scheme do not upload, publish, or bundle Hadith. No production pack has been published.
