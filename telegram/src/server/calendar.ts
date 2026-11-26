import bundledFeed from '../../../web/public/calendar/corrections-v1.json'
import rawEvents from '../../../shared/events.json'
import { calendarStarts, validateEvents } from '../../../web/src/calendar.ts'
import type { CalendarData, Event } from '../core/calendar.ts'
import { baseline, dayIn, hijri, monthIndex } from '../core/day.ts'
import { log } from './log.ts'

const FEED_URL = 'https://xn--pgbou4cf.com/calendar/corrections-v1.json'
const MAX_BYTES = 5_000_000
const YEARS = 5
const FIRST_YEAR = 1350
const LAST_YEAR = 1500

const arabic = validateEvents(rawEvents, 'ar')
const EVENTS: Event[] = validateEvents(rawEvents, 'en').map((event, index) => ({
  id: event.id,
  month: event.month,
  date: event.day,
  year: event.historicalYear,
  title: { en: event.title, ar: arabic[index]!.title },
}))

/** Month starts for the years around [now]. Throws when the feed is invalid. */
export function buildCalendar(feed: unknown, now = Date.now()): CalendarData {
  const start = calendarStarts(feed)
  const year = hijri(baseline, dayIn(now, 'UTC'))!.year
  const first = monthIndex(Math.max(FIRST_YEAR, year - YEARS), 1)
  const last = monthIndex(Math.min(LAST_YEAR, year + YEARS), 12)
  const starts: number[] = []
  // One past the last month, to close it.
  for (let month = first; month <= last + 1; month++) starts.push(start(month))
  const rows = (feed as { announcements: { method: string; sourceID: string; month: any }[] })
    .announcements
  const confirmed = rows
    .filter(row => row.sourceID === 'naked-eye-middle-east' && row.method === 'nakedEye')
    .map(row => monthIndex(row.month.year, row.month.month))
  return { months: { first, starts }, confirmed, events: EVENTS }
}

export class CalendarSource {
  private feed: unknown
  private cached: { day: number; data: CalendarData } | null = null

  constructor(
    private readonly request: (url: string, init: RequestInit) => Promise<Response> = fetch,
    initial: unknown = bundledFeed,
  ) {
    buildCalendar(initial)
    this.feed = initial
  }

  current(now = Date.now()): CalendarData {
    const day = dayIn(now, 'UTC')
    if (this.cached?.day !== day) this.cached = { day, data: buildCalendar(this.feed, now) }
    return this.cached.data
  }

  /** Keeps the last good feed on any failure. */
  async refresh(): Promise<boolean> {
    try {
      const response = await this.request(FEED_URL, { signal: AbortSignal.timeout(20_000) })
      if (!response.ok || (response.url && !response.url.startsWith('https://')))
        throw new Error('Feed unavailable')
      const body = await response.arrayBuffer()
      if (body.byteLength > MAX_BYTES) throw new Error('Feed too large')
      const feed: unknown = JSON.parse(new TextDecoder().decode(body))
      buildCalendar(feed)
      this.feed = feed
      this.cached = null
      return true
    } catch (error) {
      log('calendar.refresh_failed', error)
      return false
    }
  }
}
