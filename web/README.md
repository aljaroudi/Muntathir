# Muntathir website

Static Arabic (`/`) and English (`/en/`) site built with Astro, Tailwind CSS, Bun and Vite+. Pages render fully without JavaScript; the language switch is plain links (no redirects or cookies).

## Development

Node >=22.22 and Bun 1.4.4 (pinned in `package.json`).

```sh
cd web
bun install --frozen-lockfile
bun run dev -- --background   # manage with: bun run astro -- dev status|logs|stop
bun run format                # Vite+ formatting (skips .astro; Astro checks those)
bun run validate              # format check, lint, Astro/TypeScript check, build, output tests
bun run preview               # serve production output
```

`bun test` checks built output, so run `bun run build` first. The first build needs network access: Astro downloads and self-hosts the Google fonts (Noto Sans Arabic, Amiri for the Quran verse).

Git hooks (from the repository root): `git config core.hooksPath .githooks`. Pre-commit runs Swift and Vite+ format checks and web lint; pre-push runs Apple tests, web type checks, build and output tests. Hooks never stage files and need Bun on PATH (including for GUI Git clients) plus installed web dependencies.

## Layout

- `src/i18n.ts`: typed Arabic and English copy.
- `src/site.ts`: canonical origin, localized paths, App Store link.
- `src/components/Landing.astro`: shared layout and metadata.
- `src/styles/global.css`: Tailwind theme tokens and fonts; layout uses Tailwind utilities.
- `public/social/`: localized 1200×630 social images.
- `public/marketing/`: phone-tour manifest, WebP screenshots and WebM video, exported by `just lane ios web_media` (run `just lane ios marketing` first to recapture). The exporter validates both locales before replacing files; web builds need no simulator.

Don't add pricing, ratings or unsupported claims.

## Vercel

- Root Directory `web`, with **Include source files outside of the Root Directory in the Build Step** enabled ([docs](https://vercel.com/docs/monorepos/monorepo-faq)) so `shared/events.json` is available. Changes to shared inputs must trigger a web deploy; disable skipping of unaffected projects if it excludes them.
- `vercel.json` sets Astro, `bun install --frozen-lockfile`, `bun run build` and `dist`. No adapter, functions or secrets.
- Domain: **منتظر.com** (DNS records from Vercel). Never use the preview hostname as the canonical origin.
- `VERCEL_ENV=preview` builds emit `noindex, nofollow` and a disallow-all robots.txt. That isn't access control; use preview protection for private previews.

Check preview output locally, then restore production output:

```sh
VERCEL_ENV=preview bun run build && VERCEL_ENV=preview bun test
bun run build && bun test
```

## Calendar

- **Corrections feed:** `public/calendar/corrections-v1.json` is served at `/calendar/corrections-v1.json` and fetched by the apps (ETag, last-good cache). Keep the envelope even with no announcements, and never publish fixture announcements. Source IDs, validation and publication rules: [apple/Shared/README.md](../apple/Shared/README.md). After deploying, confirm the production URL returns 200 and a valid v1 payload.
- **Events:** edit `shared/events.json` (also bundled by the apps). Each `title` needs `en`; missing `ar` falls back to English. Invalid data fails the build.
- **ICS feeds:** `/calendar/ar.ics` and `/calendar/en.ics` (linked via `webcal:`) are built from `naked-eye-middle-east` / `nakedEye` announcements in the checked-in feed, falling back to Umm al-Qura, with month resolution mirroring Apple's `CalendarEngine`. Events are all-day civil dates. Each build covers the previous, current and next five Hijri years, so rebuild at least yearly. UIDs are stable. After deploying, check both URLs return 200 with `Content-Type: text/calendar; charset=utf-8`.
- **Calendar pages:** `/calendar/` and `/en/calendar/` show the current Hijri year without JavaScript; year pages `/calendar/1350/`–`/calendar/1500/` (and `/en/calendar/{year}/`) are pre-rendered with canonical URLs and sitemap entries. Today follows the visitor's civil date (no sunset rollover); unconfirmed future months are labeled estimates.

Feeds and pages never fetch live data: publish reviewed announcements to the corrections file, then rebuild and deploy.
