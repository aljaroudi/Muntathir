import { describe, expect, test } from "bun:test"
import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
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
    const html = readFileSync(join("dist", paths[locale], "index.html"), "utf8")
    test("renders localized content and accessible document structure without JavaScript", () => {
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
    test("provides canonical, reciprocal language links and factual structured data", () => {
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
      expect(html).toContain(translations[locale].hero.note)
    })
    test("local links, anchors and assets exist", () => {
      for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
        const value = match[1]
        if (value.startsWith("#")) {
          expect(html).toContain(`id="${value.slice(1)}"`)
        } else if (value.startsWith("/")) {
          const target = join("dist", value.endsWith("/") ? `${value}index.html` : value)
          expect(existsSync(target)).toBe(true)
        }
      }
      const image = readFileSync(`dist/social/${locale}.png`)
      expect(image.readUInt32BE(16)).toBe(1200)
      expect(image.readUInt32BE(20)).toBe(630)
    })
    test("preview builds are noindex; production builds are indexable", () => {
      expect(html.includes('name="robots" content="noindex, nofollow"')).toBe(isPreview)
    })
  })
}

test("sitemap and robots agree with production URLs and environment", () => {
  const robots = readFileSync("dist/robots.txt", "utf8")
  const sitemap = readFileSync("dist/sitemap.xml", "utf8")
  expect(robots).toContain(isPreview ? "Disallow: /" : `Sitemap: ${site.href}sitemap.xml`)
  for (const path of Object.values(paths)) {
    expect(sitemap).toContain(`<loc>${new URL(path, site).href}</loc>`)
  }
})
