import { isPreview, site } from "../site"

export function GET() {
  return new Response(
    isPreview
      ? "User-agent: *\nDisallow: /\n"
      : `User-agent: *\nAllow: /\nSitemap: ${new URL("/sitemap.xml", site).href}\n`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } }
  )
}
