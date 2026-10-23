import { site, paths } from "../site"

export function GET() {
  const urls = Object.values(paths).map(path => new URL(path, site).href)
  const alternates = Object.entries(paths)
    .map(
      ([locale, path]) =>
        `<xhtml:link rel="alternate" hreflang="${locale}" href="${new URL(path, site).href}"/>`
    )
    .join("")
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${["/privacy/", "/en/privacy/"].map(path => `<url><loc>${new URL(path, site).href}</loc></url>`).join("")}${urls.map(url => `<url><loc>${url}</loc>${alternates}<xhtml:link rel="alternate" hreflang="x-default" href="${site.href}"/></url>`).join("")}</urlset>`,
    { headers: { "Content-Type": "application/xml; charset=utf-8" } }
  )
}
