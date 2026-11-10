import { site, paths } from '../site'
import { calendarYears, calendarPath } from '../calendar-view'

export function GET() {
  function absolute(path: string) {
    return new URL(path, site).href
  }
  function localized(ar: string, en: string) {
    return [ar, en]
      .map(
        path => `<url><loc>${absolute(path)}</loc><xhtml:link rel="alternate" hreflang="ar" href="${absolute(ar)}"/><xhtml:link rel="alternate" hreflang="en" href="${absolute(en)}"/><xhtml:link rel="alternate" hreflang="x-default" href="${absolute(ar)}"/></url>`
      )
      .join('')
  }
  const pages =
    localized(paths.ar, paths.en) +
    calendarYears
      .map(year => localized(calendarPath('ar', year), calendarPath('en', year)))
      .join('') +
    ['/privacy/', '/en/privacy/'].map(path => `<url><loc>${absolute(path)}</loc></url>`).join('')
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${pages}</urlset>`,
    { headers: { 'Content-Type': 'application/xml; charset=utf-8' } }
  )
}
