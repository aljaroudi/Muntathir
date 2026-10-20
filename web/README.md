# Muntathir website

Static Arabic and English landing page built with Astro, Tailwind CSS, Bun, and Vite+. Arabic lives at `/`; English lives at `/en/`. Both pages render fully without JavaScript. The language switch uses ordinary links, with no browser-language redirects or cookies.

## Local development

Use Node >=22.22 and Bun 1.4.3 (recorded in `package.json`).

```sh
cd web
bun install --frozen-lockfile
bun run dev -- --background
```

Use `bun run astro -- dev status`, `bun run astro -- dev logs`, and `bun run astro -- dev stop` to manage the background server.

```sh
bun run format       # Explicitly format source files
bun run validate     # Formatting, lint, Astro/TypeScript checks, build, output tests
bun run preview      # Serve production output
```

`bun test` checks built output, so run `bun run build` first. Vite+ provides linting; Vite+ formats its supported source files. It currently skips `.astro` templates; those stay manually formatted and are checked by Astro. Astro handles framework compilation and type checking. The scaffold was created with:

```sh
vp create astro --package-manager bun --no-git --no-hooks --no-agent --no-editor --no-interactive -- web --template minimal --no-install --no-git --yes
```

## Content and assets

- `src/i18n.ts`: complete, typed Arabic and English copy.
- `src/site.ts`: canonical origin, localized paths, and App Store destination.
- `src/components/Landing.astro`: shared layout, accessible content, and metadata.
- `src/styles/global.css`: Tailwind theme tokens, language-level fonts, and shared accessibility defaults. Layout and component styles use Tailwind utilities.
- `scripts/social.ts`: produces localized 1200×630 PNG social images with the bundled OFL-licensed Amiri font. Browser fonts use Astro’s stable `fonts` configuration with Google providers: Inter, Noto Sans Arabic, and Amiri. Astro downloads and self-hosts the fonts at build time; the initial build requires network access. The bundled TTF is used only by the social-image renderer.

The prayer card is an illustration, not a live calculation or exact app screenshot. The App Store URL is intentionally retained before launch. Once the listing goes live, update the launch note and availability FAQ in **both** languages. Do not add pricing, ratings, or claims without evidence.

## Git hooks

From the repository root:

```sh
git config core.hooksPath .githooks
```

Pre-commit preserves Swift formatting checks and adds Vite+ formatting checks for supported files and web lint. Pre-push preserves Apple tests and adds web type checks, a production build, and build-output tests. Hooks never stage files. Both hooks require the existing Apple tools plus Bun on PATH and installed web dependencies. GUI Git clients must inherit a PATH containing Bun.

## Vercel

Import the repository and set **Root Directory** to `web`. The checked-in `vercel.json` selects Astro, `bun install --frozen-lockfile`, `bun run build`, and `dist` output. Use a supported Node version satisfying `engines.node`. No server adapter, runtime functions, or secrets are needed.

Attach **منتظر.com** in Vercel's Domains settings and apply the DNS records Vercel supplies. The URL API normalizes the internationalized hostname consistently for canonical URLs, social metadata, and sitemap entries. Do not substitute the preview hostname as the canonical origin.

Vercel sets `VERCEL_ENV=preview` for preview builds. Those builds emit `noindex, nofollow` on both pages and a robots.txt that disallows crawling. Production builds allow indexing. Preview protection is still recommended for private previews; robots directives are not access controls.

To verify the preview output locally:

```sh
VERCEL_ENV=preview bun run build
VERCEL_ENV=preview bun test
bun run build
bun test
```

The final two commands restore and check production output. Deployment and DNS changes are not performed by these scripts.
