import { Resvg } from "@resvg/resvg-js"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { translations } from "../src/i18n"
import type { Locale } from "../src/site"

function escape(text: string) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;")
}
const icon = (await readFile("public/favicon.svg")).toString("base64")
await mkdir("public/social", { recursive: true })
for (const locale of ["ar", "en"] satisfies Locale[]) {
  const t = translations[locale]
  function text(value: string) {
    return escape(locale === "ar" ? `\u202B${value}\u202C` : value)
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
    <rect width="1200" height="630" fill="#f7f5ee"/>
    <circle cx="1020" cy="315" r="300" fill="#e6ebd9"/>
    <circle cx="1020" cy="315" r="260" stroke="#b5c2a4" fill="none"/>
    <rect x="40" y="40" width="1120" height="550" rx="12" fill="none" stroke="#d2d9c5"/>
    <image href="data:image/svg+xml;base64,${icon}" x="920" y="215" width="200" height="200"/>
    <text x="460" y="140" text-anchor="middle" direction="${locale === "ar" ? "rtl" : "ltr"}" unicode-bidi="embed" font-family="Amiri" font-size="36" fill="#345442">${text(t.name)}</text>
    <text x="460" y="280" text-anchor="middle" direction="${locale === "ar" ? "rtl" : "ltr"}" unicode-bidi="embed" font-family="Amiri" font-size="82" fill="#203f35">${text(t.hero.first)}</text>
    <text x="460" y="390" text-anchor="middle" direction="${locale === "ar" ? "rtl" : "ltr"}" unicode-bidi="embed" font-family="Amiri" font-size="82" fill="#4d6d50">${text(t.hero.second)}</text>
    <text x="460" y="510" text-anchor="middle" direction="${locale === "ar" ? "rtl" : "ltr"}" unicode-bidi="embed" font-family="Amiri" font-size="30" fill="#5c685f">${text(t.hero.eyebrow)}</text>
  </svg>`
  const image = new Resvg(svg, {
    font: {
      fontFiles: ["scripts/fonts/Amiri-Regular.ttf"],
      loadSystemFonts: false,
    },
  }).render()
  await writeFile(`public/social/${locale}.png`, image.asPng())
}
