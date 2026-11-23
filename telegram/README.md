# Muntathir on Telegram

Bot and Mini App: prayer times, Hijri calendar and events, daily ayah, search, and readers for Quran, Hadith, supplications and rulings. Arabic and English. Private chats only, no reminders. The only stored user data is a `/language` choice, keyed by a keyed hash of the account ID.

```text
Telegram ── long polling ──┐
                           ├─ com.muntathir.telegram: one Bun process on 127.0.0.1:8790
tg.xn--pgbou4cf.com ───────┘    ├─ Mini App + /api, same origin
  existing muntathir-search     ├─ read-only SQLite content
  tunnel, second hostname       └─ POST 127.0.0.1:8788/v1/search (backend, unchanged)
```

The bot needs nothing inbound. The Mini App does: Telegram only gives clients its URL, and each user's phone loads it over HTTPS.

## Develop

```sh
cd telegram && bun install --frozen-lockfile
just telegram-data   # APFS clones of the content DBs into telegram/.data
just telegram-check
```

Content tests skip without `.data`. Generated DBs come from the main checkout, or `MUNTATHIR_CONTENT`.

Don't run `src/main.ts` with the production token: a second poller stops the live bot with a 409. Use a separate test bot, or `TELEGRAM_POLLING=false`.

## Rules

- **Prayer:** must equal `PrayerCalculator.kt` to the minute (`test/prayer-vectors.csv`). `adhan` is pinned: its main branch changes the solver and polar defaults.
- **Calendar:** `web/src/calendar.ts` resolves months on the server; clients get month starts. The date changes at midnight, the verse and events at Jafari sunset.
- **Without a location** the bot uses Riyadh's civil date (labeled) and, like the website and unlike iOS, still applies confirmed sightings.
- **Content:** readers follow `HadithReader.swift` and `RulingsReader.swift`. Never edit Quran text. Rulings are plain text, always with authority, notice and official link.
- **IDs** are hashes of stable keys (`src/server/ids.ts`). Changing a key breaks shared links.
- **Privacy:** log only through `src/server/log.ts`. No IDs, text, coordinates or token, and never raw grammY errors. Keep the Telegram section of the privacy page true.
- **Search:** per-user limits use a synthetic loopback `CF-Connecting-IP`, which needs `SEARCH_TRUST_TUNNEL=true` in the backend. The global and daily embedding budgets are shared with the apps.

## Hosting

Everything live is in `~/Library/Application Support/Muntathir/telegram/`: `.env`, `logs/`, `state/` (language choices; deleting it resets them), `releases/<sha>-<data>`, and `current`. Switching branches or deleting the checkout doesn't affect it.

`.env` (mode 600):

```sh
TELEGRAM_BOT_TOKEN=
# TELEGRAM_DAILY_SEARCH_LIMIT=5000
```

First setup:

1. Create `.env`.
2. `just telegram-release` (builds only, while the service isn't installed)
3. `just telegram-install --apply`
4. In the Cloudflare dashboard, open the `muntathir-search` tunnel and add a public hostname (published application route): subdomain `tg`, domain `منتظر.com`, service `http://127.0.0.1:8790`. It creates the DNS record; no login, token or restart is needed.
5. `just telegram-configure`, then `just telegram-configure --apply`.
6. In @BotFather: disable groups, set the Main Mini App to `https://tg.xn--pgbou4cf.com/` (needed for share links) and the privacy URL to `https://xn--pgbou4cf.com/privacy/`. Leave origin protection on.

Afterwards `just telegram-release` builds from a clean commit, smoke-tests without polling, switches, and rolls back if unhealthy. `just telegram-release --rollback` returns to the previous release. Two are kept.

The agent starts after login (FileVault), so log in after a reboot.

The tunnel is shared with search:

- `backend/cloudflare_setup.py` replaces the tunnel's whole ingress list. After rerunning it, add the Telegram hostname again.
- It runs under `com.muntathir.search`, so a backend deploy briefly interrupts the Mini App. The bot keeps answering.
