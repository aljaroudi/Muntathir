import { describe, expect, test } from "bun:test"
import { calendarYears, calendarPath } from "../src/calendar-view"
import { translations } from "../src/i18n"
import { appStore, site, paths, isPreview, type Locale } from "../src/site"

function shape(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(shape)
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, shape(child)]))
  }
  expect(typeof value).toBe("string")
  expect((value as string).trim().length).toBeGreaterThan(0)
  return "text"
}

test("both languages have complete, nonempty translation trees", () => {
  expect(shape(translations.ar)).toEqual(shape(translations.en))
})

for (const locale of ["ar", "en"] satisfies Locale[]) {
  describe(locale, () => {
    const page = () => Bun.file(`dist${paths[locale]}index.html`).text()
    test("renders localized content and accessible document structure without JavaScript", async () => {
      const html = await page()
      expect(html).toContain(`lang="${locale}"`)
      expect(html).toContain(`dir="${locale === "ar" ? "rtl" : "ltr"}"`)
      expect(html).toContain(translations[locale].hero.first)
      expect(html).toContain(translations[locale].faq.items[0].a)
      expect(html.match(/<h1\b/g)?.length).toBe(1)
      expect(html).toContain('href="#main"')
      expect(html).toContain('lang="ar" hreflang="ar"')
      expect(html).toContain('lang="en" hreflang="en"')
      expect(html).not.toContain("undefined")
    })
    test("provides canonical, reciprocal language links and factual structured data", async () => {
      const html = await page()
      expect(html).toContain(`rel="canonical" href="${new URL(paths[locale], site).href}"`)
      for (const [language, path] of Object.entries(paths)) {
        expect(html).toContain(`hreflang="${language}" href="${new URL(path, site).href}"`)
      }
      expect(html).toContain(`hreflang="x-default" href="${site.href}"`)
      const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]
      expect(json).toBeDefined()
      const schema = JSON.parse(json!)
      expect(schema["@type"]).toBe("SoftwareApplication")
      expect(schema.installUrl).toBe(appStore)
      expect(schema.offers).toBeUndefined()
      expect(schema.aggregateRating).toBeUndefined()
      expect(html).toContain(`href="${appStore}"`)
    })
    test("local links, anchors and assets exist", async () => {
      const html = await page()
      for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
        const value = match[1]
        if (value.startsWith("#")) {
          expect(html).toContain(`id="${value.slice(1)}"`)
        } else if (value.startsWith("/")) {
          const target = `dist${value.endsWith("/") ? `${value}index.html` : value}`
          expect(await Bun.file(target).exists()).toBe(true)
        }
      }
      const image = new DataView(await Bun.file(`dist/social/${locale}.png`).arrayBuffer())
      expect(image.getUint32(16)).toBe(1200)
      expect(image.getUint32(20)).toBe(630)
    })
    test("preview builds are noindex; production builds are indexable", async () => {
      expect((await page()).includes('name="robots" content="noindex, nofollow"')).toBe(isPreview)
    })
  })
}

test("sitemap and robots agree with production URLs and environment", async () => {
  const robots = await Bun.file("dist/robots.txt").text()
  const sitemap = await Bun.file("dist/sitemap.xml").text()
  expect(robots).toContain(isPreview ? "Disallow: /" : `Sitemap: ${site.href}sitemap.xml`)
  for (const path of Object.values(paths)) {
    expect(sitemap).toContain(`<loc>${new URL(path, site).href}</loc>`)
  }
})

test("publishes confirmed calendar starts for both supported sources", async () => {
  const feed = await Bun.file("dist/calendar/corrections-v1.json").json()
  expect(feed.schemaVersion).toBe(1)
  expect(feed.announcements).toHaveLength(3)
  for (const { sourceID, method, month, start } of [
    {
      sourceID: "naked-eye-middle-east",
      method: "nakedEye",
      month: 5,
      start: { year: 2026, month: 10, day: 13 },
    },
    {
      sourceID: "naked-eye-middle-east",
      method: "nakedEye",
      month: 6,
      start: { year: 2026, month: 11, day: 12 },
    },
    {
      sourceID: "government-SA",
      method: "government",
      month: 5,
      start: { year: 2026, month: 10, day: 13 },
    },
  ]) {
    expect(feed.announcements).toContainEqual({
      id: `${sourceID}-1448-${String(month).padStart(2, "0")}`,
      revision: 1,
      sourceID,
      method,
      coverage: {
        countries: sourceID === "government-SA" ? ["SA"] : ["SA", "KW", "BH", "OM", "AE", "QA"],
        polygons: [],
      },
      month: { year: 1448, month },
      start,
    })
  }
})

test("privacy pages and support redirect are ready before deployment", async () => {
  const config = await Bun.file("vercel.json").json()
  const target =
    "https://docs.google.com/forms/d/e/1FAIpQLSdDOEiaLaS2_-cI-n5ZDNVMjHyv6OX2IPECM_dboG1qFj8bsA/viewform?usp=header"
  for (const path of ["/support", "/support/", "/en/support", "/en/support/"]) {
    expect(
      config.redirects.find((item: { source: string }) => item.source === path)?.destination
    ).toBe(target)
  }
  for (const [path, language] of [
    ["privacy", "ar"],
    ["en/privacy", "en"],
  ]) {
    const html = await Bun.file(`dist/${path}/index.html`).text()
    expect(html).toContain(`lang="${language}"`)
    expect(html).toContain("iCloud")
    expect(html).toContain("Google")
    expect(html).toContain('href="/support/"')
  }
})

for (const locale of ["ar", "en"] as const) {
  test(`${locale} event calendar is complete and accessible without JavaScript`, async () => {
    const path = locale === "ar" ? "/calendar/" : "/en/calendar/"
    const html = await Bun.file(`dist${path}index.html`).text()
    expect(html).toContain(`lang="${locale}"`)
    expect(html).toContain(`dir="${locale === "ar" ? "rtl" : "ltr"}"`)
    expect(html.match(/<h1\b/g)).toHaveLength(1)
    expect(html.match(/<section id="month-/g)).toHaveLength(12)
    expect(html).toContain('href="#main"')
    expect(html).toContain('aria-live="polite"')
    expect(html).toContain("data-year-select")
    expect(html).toContain('value="1350"')
    expect(html).toContain('value="1500"')
    expect(html).not.toContain('value="1349"')
    expect(html).not.toContain('value="1501"')
    expect(html.match(/<option\b/g)).toHaveLength(151)
    expect(html).not.toMatch(/\bdata-(previous|next|month)(?:\s|=|>)/)
    const year = Number(html.match(/data-year-value="(\d+)"/)![1])
    expect(html).toContain(
      `rel="canonical" href="${new URL(calendarPath(locale, year), site).href}"`
    )
    expect(html).toContain(`hreflang="ar" href="${new URL(calendarPath("ar", year), site).href}"`)
    expect(html).toContain(`hreflang="en" href="${new URL(calendarPath("en", year), site).href}"`)
    expect(html).toContain(`href="webcal://${site.host}/calendar/${locale}.ics"`)
    expect(html.includes('name="robots" content="noindex, nofollow"')).toBe(isPreview)
    expect(html).not.toContain("undefined")
    expect(await Bun.file("dist/sitemap.xml").text()).toContain(
      `<loc>${new URL(calendarPath(locale, year), site).href}</loc>`
    )
    const landing = await Bun.file(`dist${paths[locale]}index.html`).text()
    expect(landing).toContain(`href="${path}"`)
    expect(landing).toContain(".webp")
    expect(landing).toContain("srcset=")
    expect(landing).toContain("data-phone-preview")
    for (const feature of translations[locale].features.items)
      expect(landing).toContain(feature.title)
  })
}

test("every supported year has crawlable bilingual HTML, headings, anchors, and canonical metadata", async () => {
  const sitemap = await Bun.file("dist/sitemap.xml").text()
  for (const locale of ["ar", "en"] as const) {
    for (const year of calendarYears) {
      const path = calendarPath(locale, year)
      const html = await Bun.file(`dist${path}index.html`).text()
      expect(html).toContain(`data-year-value="${year}"`)
      expect(html).toContain(`data-fixed-year="${year}"`)
      expect(html).toContain(`rel="canonical" href="${new URL(path, site).href}"`)
      expect(html).toContain(`href="${calendarPath(locale === "ar" ? "en" : "ar", year)}" lang=`)
      expect(html.match(/<h2\b/g)).toHaveLength(12)
      expect(html).toContain('href="#month-1"')
      expect(html).toContain('<h3 id="observance-')
      expect(html).toContain('href="#observance-')
      expect(sitemap).toContain(`<loc>${new URL(path, site).href}</loc>`)
      expect(html.includes('name="robots" content="noindex, nofollow"')).toBe(isPreview)
    }
  }
  expect(await Bun.file("dist/calendar/1349/index.html").exists()).toBe(false)
  expect(await Bun.file("dist/en/calendar/1501/index.html").exists()).toBe(false)
})
