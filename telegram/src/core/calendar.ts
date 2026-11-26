import { hijri, monthIndex, type Day, type HijriDate, type Months } from './day.ts'
import { religiousSunset, type Place } from './prayer.ts'

export type Event = {
  id: string
  month: number
  date: number
  /** Historical Hijri year; negative is before the Hijra. Not a recurrence filter. */
  year?: number
  title: { ar: string; en: string }
}

/** What the server sends the Mini App: corrected month starts and the events. */
export type CalendarData = { months: Months; confirmed: number[]; events: Event[] }

export function monthDays({ first, starts }: Months, index: number): Day[] {
  const start = starts[index - first]
  const end = starts[index - first + 1]
  if (start === undefined || end === undefined) return []
  return Array.from({ length: end - start }, (_, offset) => start + offset)
}

export function eventsOn(data: CalendarData, date: HijriDate): Event[] {
  return data.events.filter(event => event.month === date.month && event.date === date.date)
}

/**
 * The day whose verse shows at [now]. The displayed date changes at midnight, but the verse and
 * events change at sunset. Without a place there's no sunset, so both change at midnight.
 */
export function religiousDay(place: Place | null, today: Day, now: number): Day {
  const sunset = place && religiousSunset(place, today)
  return sunset && now >= sunset ? today + 1 : today
}

/** Index into quran-daily-ids.json. Day 30 has its own slot. */
export function verseIndex(date: HijriDate): number {
  return (date.month - 1) * 30 + date.date - 1
}

export type Timing = 'today' | 'tonight' | 'tomorrow' | { days: number }
export type Upcoming = { day: Day; hijri: HijriDate; events: Event[]; timing: Timing }

export function upcomingEvent(
  data: CalendarData,
  place: Place | null,
  today: Day,
  now: number,
): Upcoming | null {
  const from = religiousDay(place, today, now)
  const current = hijri(data.months, from)
  if (!current) return null
  const month = monthIndex(current.year, current.month)
  for (let offset = 0; offset <= 12; offset++) {
    for (const value of monthDays(data.months, month + offset)) {
      if (value < from) continue
      const date = hijri(data.months, value)
      if (!date) continue
      const events = eventsOn(data, date)
      if (!events.length) continue
      const timing: Timing =
        value === today
          ? 'today'
          : value === today + 1
            ? place && religiousSunset(place, today)
              ? 'tonight'
              : 'tomorrow'
            : { days: value - today }
      return { day: value, hijri: date, events, timing }
    }
  }
  return null
}
