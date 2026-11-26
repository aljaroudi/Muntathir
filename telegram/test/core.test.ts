import { describe, expect, test } from 'bun:test'
import { baselineStart } from '../../web/src/calendar.ts'
import { baseline, day, dayIn, hijri } from '../src/core/day.ts'
import { nextPrayer, prayerTimes, type Method } from '../src/core/prayer.ts'

const METHOD: Record<string, Method> = { Jafari: 'jafari', Tehran: 'tehran', UmmAlQura: 'ummAlQura' }

describe('prayer', () => {
  // A sample of PrayerCalculator.kt's output for 24 places over 2025-12-25…2028-03-05.
  test('matches the Android core to the minute', async () => {
    const rows = (await Bun.file(`${import.meta.dir}/prayer-vectors.csv`).text()).trim().split('\n')
    expect(rows.length).toBeGreaterThan(1200)
    for (const row of rows) {
      const [, latitude, longitude, method, date, times] = row.split(',') as [
        string, string, string, string, string, string,
      ]
      const [y, m, d] = date.split('-').map(Number) as [number, number, number]
      const place = { latitude: Number(latitude), longitude: Number(longitude) }
      const actual = prayerTimes(place, day(y, m, d), METHOD[method]!)
      expect(`${row}|${actual.map(moment => moment.at / 1000).join(' ')}`).toBe(`${row}|${times}`)
    }
  })

  test('rejects impossible input', () => {
    expect(prayerTimes({ latitude: 91, longitude: 0 }, 20000, 'tehran')).toEqual([])
    expect(prayerTimes({ latitude: NaN, longitude: 0 }, 20000, 'tehran')).toEqual([])
    expect(prayerTimes({ latitude: 89, longitude: 0 }, day(2026, 6, 21), 'tehran')).toEqual([])
  })

  test('next prayer skips to tomorrow after Isha', () => {
    const place = { latitude: 21.4225, longitude: 39.8262 }
    const today = day(2026, 11, 22)
    const isha = prayerTimes(place, today, 'tehran').find(moment => moment.name === 'isha')!.at
    expect(nextPrayer(place, today, 'tehran', isha)).toEqual(
      prayerTimes(place, today + 1, 'tehran').find(moment => moment.name === 'fajr')!,
    )
  })
})

describe('days', () => {
  test('the bundled baseline matches the ICU calendar the website uses', () => {
    baseline.starts.forEach((start, offset) => expect(start).toBe(baselineStart(baseline.first + offset)))
  })

  test('civil day follows the zone', () => {
    const instant = Date.UTC(2026, 10, 22, 22, 30)
    expect(dayIn(instant, 'UTC')).toBe(day(2026, 11, 22))
    expect(dayIn(instant, 'Asia/Riyadh')).toBe(day(2026, 11, 23))
    expect(dayIn(instant, 'America/Los_Angeles')).toBe(day(2026, 11, 22))
  })

  test('hijri lookup', () => {
    expect(hijri(baseline, baseline.starts[0]!)).toEqual({ year: 1349, month: 12, date: 1 })
    expect(hijri(baseline, baseline.starts[0]! - 1)).toBeNull()
  })
})
