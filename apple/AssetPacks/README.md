# Quran translation delivery

Only `quran.db` ships in the iPhone/iPad app and daily-ayah widget. Thirteen translation databases remain unchanged in `Muntathir/Resources/Quran` as asset-pack inputs. The unit-test bundle includes them as fixtures; the shipping app does not.

The app requests one ordinary Apple-hosted on-demand pack for the selected translation. Auto matches the user's preferred languages, including Chinese script. Arabic and unmatched preferences show Arabic alone. Explicit choices and None override Auto. The medium widget reads the same selection and installed asset files without downloading; Lock Screen widgets remain Arabic-only. Removing the active translation selects None. Other downloaded translations stay available until removed.

## Package and validate

From the repository root, with Xcode 26 or newer selected:

```sh
python3 apple/AssetPacks/assets.py validate
python3 apple/AssetPacks/assets.py package
python3 apple/AssetPacks/assets.py check-bundle apple/build/DerivedData/Build/Products/Debug-iphonesimulator/Muntathir.app
```

Archives are written to ignored `apple/build/AssetPacks/*.aar`. Manifest IDs and `Quran/<translation-id>.db` paths are stable. Keep database schema backward-compatible: an updated pack can reach older installed app versions.

## Local delivery test

Serve the packaged archives using Apple's mock server:

```sh
xcrun ba-serve serve apple/build/AssetPacks/*.aar --host localhost
```

Use the server's reported URL and trust its development TLS certificate as instructed by the tool. The server requires a TLS identity for the supplied hostname in your keychain; if it reports “The specified item could not be found in the keychain”, configure that development identity before testing downloads. For a physical device, use the Mac's reachable hostname instead of localhost, enable Developer Mode, and set Settings → Developer → Background Assets → Development Overrides to the server URL. For Simulator, use its developer override when supported; a local server alone does not enable an override inside Simulator. Do not change production hosting keys to point at the mock server.

Build the app with its `MuntathirAssetDownloader` ExtensionKit extension. Launch with French preferred, verify Arabic appears immediately, and then verify French loads. Repeat with English, Persian, Urdu, simplified/traditional Chinese, Arabic, and an unsupported language. Switch translations while a download runs, disconnect networking, retry, relaunch offline, and remove the active translation. Verify chapters, search, saved verses, daily ayah, sharing, and the medium widget update. Check Lock Screen widgets stay Arabic-only. Confirm selection None survives relaunch and doesn't request another pack.

## Upload first; then manage in App Store Connect

Asset packs do not start with a web upload form. Upload the `.aar` archives using Transporter or its command-line tool. They appear in App Store Connect after processing: **Muntathir → TestFlight → Builds & Assets → Asset Packs**. For App Store review, use **Distribution → Asset Packs**. The web's Asset Library is for marketing media, not these databases.

The simplest route on this Mac uses Transporter's bundled `altool` with the already configured `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` in the private release environment file:

```sh
cd apple
bundle exec ruby fastlane/asset_pack_delivery.rb --list
bundle exec ruby fastlane/asset_pack_delivery.rb --upload
```

Upload only after packaging the current source files. Each repeated upload creates a new version, so check the list before retrying a partially completed batch. The helper uploads to Muntathir's fixed app ID, 6824304362, and lists received packs afterward. It does not submit review or release the app. Xcode's `xcrun altool` on this Mac currently fails with missing `Defaults.properties`; the helper uses the working binary inside Transporter instead.

For the graphical route: Transporter → Add Package → select the 13 archives in `apple/build/AssetPacks` → choose منتظِر (6824304362) → Add → Deliver. Local packaging and internal TestFlight do not require configuring a mock-server TLS certificate.

## Testing and review

1. Ensure the new `com.aljaroudi.Muntathir.AssetDownloader` target is signed with the existing `group.com.aljaroudi.Muntathir` App Group. The app, downloader, and widget access the same assets without maintaining database copies.
2. Open [Muntathir’s TestFlight Asset Packs](https://appstoreconnect.apple.com/teams/69a6de7d-f4fa-47e3-e053-5b8c7c11a4d1/apps/6824304362/testflight/assets). Wait until all 13 uploads finish processing and show Ready for Internal Testing. TestFlight automatically uses these versions for internal testers with a compatible build. Install a build containing this migration; an old TestFlight build cannot request these packs. `fastlane ios build` can export this build before external pack approval; upload that IPA through Transporter for internal testing. Distribution lanes still check pack readiness.
3. Verify downloads and offline use through internal TestFlight. Submit the packs for external testing before distributing the app to external testers.
4. Apple accepts at most 10 different asset packs per App Store review submission. Because this app has not yet been approved, include the first batch with the first app-version submission. Keep manual app release selected. Once the app is approved, submit the remaining packs separately and wait for their approval before manually releasing the app.
5. `fastlane ios readiness` verifies all 13 packs have active iOS external-TestFlight versions. For an existing published app, `readiness release:true` checks App Store availability. A first app submission checks external-TestFlight availability instead, because its App Store asset approval must happen alongside app review. Archive export separately checks the IPA contains only Arabic databases and the downloader extension.

Apple-hosted asset versions are independent of app builds: keep database schemas compatible with every installed build that references those pack IDs. Only upload/publish a new version when its contents change.

Official references: [upload asset packs](https://developer.apple.com/help/app-store-connect/manage-asset-packs/upload-apple-hosted-asset-packs/), [processing and testing statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-statuses/), [App Store review and the 10-pack limit](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-apple-hosted-asset-packs/).

Native iOS 27 localized packs remain deferred; ordinary on-demand packs support the iOS 26 minimum and explicit download/removal choices.
