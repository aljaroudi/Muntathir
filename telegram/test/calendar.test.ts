import { afterAll, describe, expect, spyOn, test } from 'bun:test'
import bundled from '../../web/public/calendar/corrections-v1.json'
import sample from '../../shared/fixtures/corrections-v1.json'
import ids from '../../apple/Muntathir/Resources/quran-daily-ids.json'
import { monthDays, religiousDay, upcomingEvent, verseIndex } from '../src/core/calendar.ts'
import { baseline, day, hijri, monthIndex } from '../src/core/day.ts'
import { religiousSunset } from '../src/core/prayer.ts'
import { buildCalendar, CalendarSource } from '../src/server/calendar.ts'

const now = Date.UTC(2026, 10, 22, 12)
const data = buildCalendar(bundled, now)
const KARBALA = { latitude: 32.616, longitude: 44.0249 }
const quiet = spyOn(console, 'log').mockImplementation(() => {})
afterAll(() => quiet.mockRestore())

describe('calendar', () => {
  test('applies the published sightings', () => {
    expect(hijri(data.months, day(2026, 11, 22))).toEqual({ year: 1448, month: 6, date: 11 })
    expect(hijri(data.months, day(2026, 10, 13))).toEqual({ year: 1448, month: 5, date: 1 })
  })

  test('every month has 29 or 30 days', () => {
    for (const feed of [bundled, sample, { schemaVersion: 1, announcements: [] }]) {
      const { months } = buildCalendar(feed, now)
      for (let index = 1; index < months.starts.length; index++)
        expect([29, 30]).toContain(months.starts[index]! - months.starts[index - 1]!)
    }
  })

  test('without announcements it is the baseline', () => {
    const { months } = buildCalendar({ schemaVersion: 1, announcements: [] }, now)
    months.starts.forEach((start, offset) =>
      expect(start).toBe(baseline.starts[months.first + offset - baseline.first]!),
    )
  })

  test('verse and events roll over at sunset, the date does not', () => {
    const today = day(2026, 11, 22)
    const sunset = religiousSunset(KARBALA, today)!
    expect(religiousDay(KARBALA, today, sunset - 1)).toBe(today)
    expect(religiousDay(KARBALA, today, sunset)).toBe(today + 1)
    expect(religiousDay(null, today, sunset)).toBe(today)
  })

  test('an event is Today, then Tonight on the eve', () => {
    const value = monthDays(data.months, monthIndex(1449, 1))[9]! // 10 Muharram
    const sunset = religiousSunset(KARBALA, value)!
    expect(upcomingEvent(data, KARBALA, value, sunset - 1)!.timing).toBe('today')
    const eve = religiousSunset(KARBALA, value - 1)!
    expect(upcomingEvent(data, KARBALA, value - 1, eve)).toMatchObject({ day: value, timing: 'tonight' })
    expect(upcomingEvent(data, null, value - 1, eve)!.day).toBeLessThanOrEqual(value)
  })

  test('every possible day has a verse, including the 30th', () => {
    expect(ids).toHaveLength(360)
    expect(verseIndex({ year: 1448, month: 1, date: 30 })).toBe(29)
    expect(verseIndex({ year: 1448, month: 12, date: 30 })).toBe(359)
  })

  test('a bad feed keeps the last good one', async () => {
    const replies = [
      () => Response.json({ schemaVersion: 1, announcements: [] }),
      () => Response.json({ schemaVersion: 2, announcements: [] }),
      () => new Response('not json'),
      () => new Response('', { status: 503 }),
      () => { throw new TypeError('offline') },
    ]
    const source = new CalendarSource(async () => replies.shift()!())
    expect(await source.refresh()).toBe(true)
    const good = source.current(now).months
    for (let attempt = 0; attempt < 4; attempt++) {
      expect(await source.refresh()).toBe(false)
      expect(source.current(now).months).toEqual(good)
    }
  })
})
