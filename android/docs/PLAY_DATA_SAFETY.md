# Play Console answers

From the P7.3 audit (2026-11-17, play-policy-insights). Fill these in when the app is created in Play Console (P7.5). Re-check them whenever a network call, SDK or permission is added.

## Data safety

**Does the app collect or share user data?** Yes, one type.

| Data type | Collected | Shared | Linked to user | Optional | Purpose | Notes |
|---|---|---|---|---|---|---|
| App activity → In-app search history | Yes | No | No | Yes | App functionality | Smart search posts the typed query (with kind, sources, chapter, languages) to the `/v1/search` endpoint only after the user taps Smart search. No identifiers; generic `Muntathir/1.0` user agent. Mark "processed ephemerally" only if the backend doesn't log queries. |

- **Encrypted in transit:** yes. The feed rejects non-HTTPS URLs and redirects, and targetSdk 28+ blocks cleartext by default.
- **Deletion requests:** nothing is kept on our side tied to a user. There are no accounts.
- **If the release ships with a Maps key:** add whatever Google's Maps SDK for Android data disclosure lists. App code itself sends no location.

Not collected (stays on the device; Auto Backup is the user's own encrypted Google backup):
- Approximate location (prayer times) and precise location (Qibla, never saved).
- Prayer records, reading time, highlights, bookmarks, recent searches, preferences.
- Camera frames (Rakaat reads brightness in memory; nothing is captured or stored).

Not declared because the user starts it: sharing verse or narration text and images through the share sheet.

## Permissions and declarations

- **Exact alarms:** `SCHEDULE_EXACT_ALARM` only (never `USE_EXACT_ALARM`). Not granted → alerts use a 10-minute window. No declaration form.
- **Location:** foreground only, no `ACCESS_BACKGROUND_LOCATION`. No declaration form.
- **Camera:** front camera, frames analysed in memory only.
- **Foreground service: declaration still required.** Our own code no longer declares a type (WorkManager's service is untyped; it only runs below API 31). But Play Asset Delivery's `com.google.android.play.core.assetpacks.ExtractionForegroundService` is merged with `foregroundServiceType="dataSync"` and `FOREGROUND_SERVICE_DATA_SYNC`. Declare **Data sync**: "Downloading and installing optional content packs (Hadith, Supplications, Quran translations, Rulings) that the user requests from Downloads", with a short video of a pack download. Don't remove the library's service; asset packs depend on it.

## App content

- **Accounts:** none, so no reviewer credentials and no account-deletion link.
- **Ads:** none. **Target audience:** adults (not designed for children).
- **Privacy policy:** reuse the iOS `privacy_url.txt`, and make sure it mentions Smart search queries.
