import type { APIRoute } from "astro"
import events from "../../../../shared/events.json"
import feed from "../../../public/calendar/corrections-v1.json"
import { generateCalendar } from "../../calendar"
import type { Locale } from "../../site"

const builtAt = new Date()

export function getStaticPaths() {
  return ["ar", "en"].map(locale => ({ params: { locale } }))
}

export const GET: APIRoute = ({ params }) =>
  new Response(generateCalendar(events, feed, params.locale as Locale, builtAt), {
    headers: { "Content-Type": "text/calendar; charset=utf-8" },
  })
