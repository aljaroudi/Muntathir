import { expect, test } from 'bun:test'
import events from '../../shared/events.json'
import { baselineStart, calendarStarts, generateCalendar } from '../src/calendar'
import { site } from '../src/site'

const empty = { schemaVersion: 1, announcements: [] }
const now = new Date('2026-10-28T00:00:00Z')
const month = 1448 * 12
const announcement = (start: string, overrides = {}) => ({
  id: 'test',
  revision: 1,
  method: 'nakedEye',
  sourceID: 'naked-eye-middle-east',
  coverage: { countries: ['SA'], polygons: [] },
  month: { year: 1448, month: 1 },
  start: Object.fromEntries(
    ['year', 'month', 'day'].map((key, i) => [key, Number(start.split('-')[i])])
  ),
  ...overrides,
})
const unfold = (ics: string) => ics.replace(/\r\n /g, '')

// Dates checked against Foundation Calendar(identifier: .islamicUmmAlQura), UTC.
test("Umm al-Qura baseline matches Apple's Foundation calendar", () => {
  for (const [year, hijriMonth, date] of [
    [1447, 1, '2025-06-26'],
    [1448, 1, '2026-06-16'],
    [1448, 9, '2027-02-08'],
    [1449, 1, '2027-06-06'],
  ] as const) {
    expect(
      new Date(baselineStart(year * 12 + hijriMonth - 1) * 86400000).toISOString().slice(0, 10)
    ).toBe(date)
  }
})

test("confirmed boundaries match Apple's forward/backward month resolution", () => {
  const start = calendarStarts({ ...empty, announcements: [announcement('2026-06-17')] })
  expect(start(month)).toBe(baselineStart(month) + 1)
  expect(start(month - 1)).toBe(baselineStart(month - 1))
  for (let cursor = month - 3; cursor <= month + 4; cursor++)
    expect([29, 30]).toContain(start(cursor + 1) - start(cursor))
  expect(start(month + 3)).toBe(baselineStart(month + 3))
  expect(calendarStarts(empty)(month)).toBe(baselineStart(month))
  expect(
    calendarStarts({
      ...empty,
      announcements: [
        announcement('2026-06-17', { sourceID: 'government-SA', method: 'government' }),
      ],
    })(month)
  ).toBe(baselineStart(month))
})

test('rejects invalid feeds, dates, coverage, and conflicting confirmations', () => {
  for (const feed of [
    { schemaVersion: 2, announcements: [] },
    { ...empty, announcements: [announcement('2026-02-30')] },
    { ...empty, announcements: [announcement('2026-07-17')] },
    {
      ...empty,
      announcements: [announcement('2026-06-17', { coverage: { countries: [], polygons: [] } })],
    },
    {
      ...empty,
      announcements: [announcement('2026-06-17'), announcement('2026-06-16', { id: 'second' })],
    },
    {
      ...empty,
      announcements: [
        announcement('2026-06-17'),
        announcement('2026-07-14', { id: 'second', month: { year: 1448, month: 2 } }),
      ],
    },
  ])
    expect(() => calendarStarts(feed)).toThrow()
})

test('corrections move all-day dates while preserving occurrence UID', () => {
  const sample = [{ ...events[0], month: 1, day: 2 }]
  const original = unfold(generateCalendar(sample, empty, 'en', now))
  const corrected = unfold(
    generateCalendar(
      sample,
      { ...empty, announcements: [announcement('2026-06-17')] },
      'en',
      new Date('2026-10-29T00:00:00Z')
    )
  )
  const uid = 'UID:husayn-arrival-karbala-1448-en@muntathir.calendar'
  expect(original).toContain(uid)
  expect(corrected).toContain(uid)
  expect(original).toContain('DTSTART;VALUE=DATE:20260617\r\nDTEND;VALUE=DATE:20260618')
  expect(corrected).toContain('DTSTART;VALUE=DATE:20260618\r\nDTEND;VALUE=DATE:20260619')
  expect(corrected).toContain('LAST-MODIFIED:20261029T000000Z')
  expect(original.match(/BEGIN:VEVENT/g)).toHaveLength(7)
  expect(original).toContain('Hijri date: 2/1/1447 AH')
  expect(original).toContain('Hijri date: 2/1/1453 AH')
})

test('skips nonexistent month days and validates events and titles', () => {
  const sample = [{ ...events[0], month: 1, day: 30 }]
  const output = unfold(generateCalendar(sample, empty, 'en', now))
  for (let year = 1447; year <= 1453; year++) {
    const month = year * 12
    expect(output.includes(`UID:husayn-arrival-karbala-${year}-en@`)).toBe(
      baselineStart(month + 1) - baselineStart(month) === 30
    )
  }
  for (const invalid of [
    [{ ...sample[0], day: 31 }],
    [sample[0], sample[0]],
    [{ ...sample[0], title: undefined }],
  ])
    expect(() => generateCalendar(invalid, empty, 'en', now)).toThrow()
  expect(() =>
    generateCalendar([{ ...sample[0], title: { ar: 'عنوان' } }], empty, 'ar', now)
  ).toThrow()
})

test('figure links do not change exported observances', () => {
  const { figure_ids, ...event } = events[0]
  expect(figure_ids).toEqual(['husayn-ibn-ali'])
  expect(generateCalendar([event], empty, 'en', now)).toBe(
    generateCalendar([events[0]], empty, 'en', now)
  )
})

test('missing Arabic title falls back to English', () => {
  const output = unfold(
    generateCalendar(
      [{ id: 'test', month: 1, day: 1, title: { en: 'English title' } }],
      empty,
      'ar',
      now
    )
  )
  expect(output).toContain('SUMMARY:English title')
})

test('generation window respects a corrected Hijri year boundary', () => {
  const output = unfold(
    generateCalendar(
      [{ ...events[0], month: 1, day: 2 }],
      { ...empty, announcements: [announcement('2026-06-17')] },
      'en',
      new Date('2026-06-16T12:00:00Z')
    )
  )
  expect(output).toContain('UID:husayn-arrival-karbala-1446-en@')
  expect(output).toContain('UID:husayn-arrival-karbala-1452-en@')
  expect(output).not.toContain('UID:husayn-arrival-karbala-1453-en@')
})

test('escapes text and folds UTF-8 safely at 75 bytes', () => {
  const prefix = 'عنوان طويل '.repeat(20)
  const title = prefix + '\\;\n,'
  const output = generateCalendar(
    [{ id: 'test', month: 1, day: 1, title: { en: title, ar: title } }],
    empty,
    'ar',
    now
  )
  expect(unfold(output)).toContain('SUMMARY:' + prefix + '\\\\\\;\\n\\,')
  expect(output.endsWith('END:VCALENDAR\r\n')).toBe(true)
  expect(output.replace(/\r\n/g, '')).not.toMatch(/[\r\n]/)
  for (const line of output.split('\r\n')) expect(Buffer.byteLength(line)).toBeLessThanOrEqual(75)
  expect(Buffer.from(output).toString('utf8')).toBe(output)
})

for (const locale of ['ar', 'en'] as const)
  test(`${locale} built feed and subscription link`, async () => {
    const output = await Bun.file(`dist/calendar/${locale}.ics`).text()
    expect(output).toContain('BEGIN:VCALENDAR\r\n')
    expect(unfold(output)).toContain(events[0]!.title[locale])
    expect(output.match(/BEGIN:VEVENT/g)!.length).toBeGreaterThan(events.length * 6)
    const html = await Bun.file(`dist/${locale === 'ar' ? '' : 'en/'}index.html`).text()
    expect(html).toContain(`href="webcal://${site.host}/calendar/${locale}.ics"`)
  })

test('event calendar groups and sorts days with the same corrected dates as ICS', async () => {
  const { calendarMonths, validateEvents } = await import('../src/calendar')
  const { renderCalendar } = await import('../src/calendar-view')
  const sample = [
    { id: 'later', month: 1, day: 5, title: { en: 'Later' } },
    { id: 'first', month: 1, day: 2, title: { en: 'First' } },
    { id: 'same-day', month: 1, day: 2, title: { en: 'Same day' } },
  ]
  const feed = { ...empty, announcements: [announcement('2026-06-17')] }
  const start = calendarStarts(feed)
  const today = new Date('2026-06-18T00:00:00Z')
  const validated = validateEvents(sample, 'en')
  const months = calendarMonths(validated, start, [month], 1448, today)
  expect(months).toHaveLength(12)
  expect(months[0]!.days.map(row => row.day)).toEqual([2, 5])
  expect(months[0]!.days[0]!.events.map(event => event.id)).toEqual(['first', 'same-day'])
  expect(months[0]!.days[0]).toMatchObject({ today: true, next: true, distance: 0 })
  expect(months[1]!.days).toEqual([])
  const html = renderCalendar(validated, start, [month], 1448, 'en', today)
  const ics = unfold(generateCalendar(sample, feed, 'en', today))
  for (const row of months.flatMap(value => value.days)) {
    const date = new Date(row.date * 86400000).toISOString().slice(0, 10)
    expect(html).toContain(`datetime="${date}"`)
    for (const event of row.events) {
      expect(ics).toContain(`UID:${event.id}-1448-en@`)
      expect(ics).toContain(`DTSTART;VALUE=DATE:${date.replace(/-/g, '')}`)
    }
  }
  expect(html).toContain('No events')
})

test('expected months exclude confirmed future boundaries and current/past months', async () => {
  const { calendarMonths, validateEvents } = await import('../src/calendar')
  const start = calendarStarts(empty)
  const sample = validateEvents(events, 'en')
  const months = calendarMonths(sample, start, [month + 1], 1448, new Date('2026-06-18Z'))
  expect(months[0]!.expected).toBe(false)
  expect(months[1]!.expected).toBe(false)
  expect(months[2]!.expected).toBe(true)
  expect(calendarMonths(sample, start, [], 1447, now).every(value => !value.expected)).toBe(true)
  expect(calendarMonths(sample, start, [], 1449, now).every(value => value.expected)).toBe(true)
  expect(
    calendarMonths(sample, start, [], 1449, now)
      .flatMap(value => value.days)
      .some(value => value.next)
  ).toBe(false)
})

test('month models skip absent day 30 and handle year limits and corrected rollover', async () => {
  const { calendarMonths, currentMonthIndex, validateEvents } = await import('../src/calendar')
  const start = calendarStarts({ ...empty, announcements: [announcement('2026-06-17')] })
  expect(currentMonthIndex(start, new Date('2026-06-16Z'))).toBe(month - 1)
  expect(currentMonthIndex(start, new Date('2026-06-17Z'))).toBe(month)
  const sample = validateEvents(
    [{ id: 'last-day', month: 1, day: 30, title: { en: 'Last day' } }],
    'en'
  )
  for (const year of [1350, 1448, 1449, 1500]) {
    const months = calendarMonths(sample, start, [], year, now)
    expect(months).toHaveLength(12)
    for (let i = 0; i < 12; i++)
      expect([29, 30]).toContain(start(year * 12 + i + 1) - start(year * 12 + i))
    expect(months[0]!.days.length).toBe(start(year * 12 + 1) - start(year * 12) === 30 ? 1 : 0)
  }
})

test('calendar rendering escapes event markup and uses localized labels', async () => {
  const { validateEvents } = await import('../src/calendar')
  const { renderCalendar } = await import('../src/calendar-view')
  const sample = validateEvents(
    [{ id: 'test', month: 1, day: 1, title: { en: '<img src=x onerror="alert(1)">' } }],
    'ar'
  )
  const html = renderCalendar(sample, calendarStarts(empty), [], 1449, 'ar', now)
  expect(html).not.toContain('<img')
  expect(html).toContain('&lt;img')
  expect(html).toContain('متوقّع')
  expect(html).toContain('لا توجد مناسبات')
})

test('next-event highlighting rolls into the next year only when no events remain', async () => {
  const { calendarMonths, validateEvents } = await import('../src/calendar')
  const start = calendarStarts(empty)
  const sample = validateEvents(
    [{ id: 'new-year', month: 1, day: 1, title: { en: 'New year' } }],
    'en'
  )
  const date = new Date((start(1449 * 12) - 1) * 86400000)
  expect(
    calendarMonths(sample, start, [], 1448, date)
      .flatMap(month => month.days)
      .some(day => day.next)
  ).toBe(false)
  const first = calendarMonths(sample, start, [], 1449, date)[0]!.days[0]!
  expect(first).toMatchObject({ next: true, today: false, distance: 1 })
})
