# Apple apps

Native iPhone/iPad app and Apple Watch companion using Swift 6 and SwiftUI. Requires iOS 26+ / watchOS 26+ and a compatible Xcode installation.

Open `Muntathir.xcodeproj`. Use `Muntathir` for iPhone/iPad, `MuntathirWatch` for Watch, and `MuntathirWidgets` for widget development. Select your signing team for device builds. Enable iCloud Key-Value Store for the iPhone app and `group.com.aljaroudi.Muntathir` for app/widget targets on both platforms.

## Commands

From repository root: `make apple-format`, `make apple-build`, and `make apple-test`. Build uses an unsigned iOS Simulator destination and includes embedded extensions. Tests select a compatible iPhone simulator; set `TEST_DESTINATION` to override it.

## Components

- [iPhone/iPad](Muntathir/): navigation, preferences, notifications, and daily ayah.
- [iOS/CarPlay widgets](MuntathirWidgets/).
- [Watch app](MuntathirWatch/) and [complications](MuntathirWatchWidgets/).
- [Shared calendar, feed contract, and content provenance](Shared/).
- [Unit/integration tests](MuntathirTests/) and [UI tests](MuntathirUITests/).

Core Swift sources live in `Muntathir/Core` and are reused directly by Apple targets. Adhan 1.5.0 is pinned in the Xcode project's package resolution file. There is no separate prayer engine. Shared fixtures are reference data; test copies are bundle resources.

Apple Weather marks in `Muntathir/Resources/WeatherAttribution.xcassets` are original 3× PNGs downloaded on 2026-10-28 from `https://weatherkit.apple.com/attribution/{language}` using its `logoLight@3x` and `logoDark@3x` URLs. Both app and widget bundle them. The 13 artwork languages match the app languages except Persian and Urdu, which use English because Apple returns generic marks for those codes. Simplified and Traditional Chinese use Apple's `zh-CN` and `zh-TW` artwork. Keep original artwork and filenames when updating; appearance variants use black on light backgrounds and white on dark backgrounds.

`AppIcon.icon` is the shared Icon Composer source for iPhone/iPad and Watch in Debug and Release. Widget extensions use their containing app's identity. Quran Arabic text must never be edited. `QPCHafs.woff2` is registered through `UIAppFonts` with PostScript name `KFGQPCHAFSUthmanicScript-Regula`. Arabic Hadith uses bundled `Lateef-Light.ttf` (`Lateef-Light`) in previews, selectable text, and shared images. Both readers share the text-size setting and retain Dynamic Type.

## Release checks

Validate real-device compass/calibration, notifications/background delivery, paired Watch synchronization and complications, CarPlay layouts, signed App Group provisioning, two-device iCloud sync, VoiceOver, and accessibility sizes. Review event dates and Arabic titles editorially.

The app refreshes the version-one calendar feed from https://منتظر.com/calendar/corrections-v1.json on launch/foreground, source changes, and scheduled background refresh. The website publishes confirmed starts for 1448-05 on 2026-10-13 for Middle East naked-eye sightings and Saudi government announcements. Push delivery remains unconfigured. Simulator tests cannot prove hardware behavior or deployed feed delivery.

## Fastlane

See [release automation](fastlane/SETUP.md) for local commands, bilingual store metadata, styled screenshots, sunrise-to-sunset previews, and the dedicated GitHub Actions runner.

## Local Hadith development

Tools → Hadith searches Arabic and English across the library. Opening a collection shows searchable contents grouped by source book or volume; opening a chapter shows paginated narrations. Collection contents also provide narration search and number lookup. Number lookup uses source numbering; repeated numbers show chapter/volume references. Al-Kafi and Uyun Akhbar al-Rida volumes share catalog entries without changing source IDs or text.

Tools → Supplications lists the 54 prayers of al-Sahifa al-Sajjadiyya under one section heading. Search matches prayer titles and full text, ignoring Arabic diacritics, with title matches first. Each result opens directly into continuous reading with highlights, copying, sharing, and text sizing; there is no narration metadata or previous/next navigation. The introduction is excluded from prayer search. Supplications use their own on-demand `supplications` asset pack and Downloads entry, independently of Hadith. Source identities remain unchanged so saved highlights continue to resolve after downloading the new pack.

Place the extracted hadith `app/data` contents in `temp/hadith-data/`, then run `uv run build/hadith/build.py --sittah --four`. The generated database is delivered through one on-demand Apple-hosted pack; see [asset delivery](AssetPacks/). The app and widget do not bundle Hadith. Unit tests include the generated database as a fixture. Generated databases and source corpora are ignored by Git.

Hadith schema v7 stores assessments only for the Six Books (Bukhari, Muslim, Abu Dawud, Tirmidhi, Nasai, and Ibn Majah) in `hadith_grading`, joined to `grader` by its optional stable ID. Each record retains Arabic/English judgments and references plus original source text; `hadith.grade` no longer exists. `status` distinguishes judgments, “not included” coverage, and unparsed source values. The importer merges verified spelling aliases and duplicate assessments, preserves distinct judgments/references from the same scholar, and reports unparsed inputs. It does not assign broad authenticity categories. Rebuild the database whenever updating this schema; older asset databases are incompatible with the reader.


The reader keeps 50 previews at a time and pages by source ID. It prepares Markdown and match-centered previews one narration at a time off the main thread, retaining full text only for the open narration. Arabic highlights preserve source diacritics; English highlights use the FTS Porter stem matches, including narrator matches. Production asset packs and selective book downloads are deferred; the current development bundle adds roughly 376 MB before packaging compression.

Arabic book and author names are loaded from `build/hadith/data/books-and-authors.json`. Blank translations retain source values. Rebuild after editing that file.

Original Arabic Kafi section names are recorded in `build/hadith/data/kafi-chapters.json`, keyed by book ID and source filename, with Arabic edition references and first/last narration URLs. These are attested headings, not translations of the English titles. The importer fills missing Arabic names only when the English title and narration boundaries still match; existing source Arabic names take precedence. Headings continue to follow app language independently of the English narration toggle.

Al-Kafi lists the 35 printed kitābs. The author introduction is not imported, so volume 1 numbering starts at the first narration. Zakat remains one kitāb stored as two sections. العتق، الحدود، and الديات are restored from the Dar al-Kutub edition because the Thaqalayn files omit them. The three volume 7 sections that follow use the kitāb those narrations belong to: الشهادات، القضاء والأحكام، and الأيمان والنذور والكفارات. Tahdhib al-Ahkam and Man La Yahduruh al-Faqih sections use the printed Arabic headings in `tahdhib-chapters.json` and `faqih-chapters.json`. A volume or section with no heading of its own is الجزء plus an Arabic-Indic number. Rebuild and repackage the local Hadith asset after changing this metadata; an already installed asset retains its old copy until replaced.

Hadith search ranks literal whole-word matches first, literal substring matches second, and stemmed or ordered-fallback matches last, with phase-aware pagination. Saved searches from the earlier ranking restart at page one while preserving the query and scope. Root/lemma mappings are excluded unless the builder receives `--experimental-morphology`; enabling the flag does not change app search. Rijal is not built or delivered.

Introductions use a separate `introduction` table and reader. `hadith_reading` stores primary-text word counts and display numbers; existing narration source keys and text remain unchanged. Reading estimates use 200 words per minute, rounded up to one minutes/hours unit. Adjustable reading text targets 175% line height, with natural font height as its minimum; fixed Mushaf pages retain their layout.
