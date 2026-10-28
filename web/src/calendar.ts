import assert from "node:assert/strict"
import type { Locale } from "./site"

const dayMs = 86_400_000
const baseline = new Intl.DateTimeFormat("en-u-ca-islamic-umalqura-nu-latn", {
  timeZone: "UTC",
  year: "numeric",
  month: "numeric",
  day: "numeric",
})
assert.equal(baseline.resolvedOptions().calendar, "islamic-umalqura")

export function hijri(date: Date) {
  const parts = baseline.formatToParts(date)
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find(part => part.type === type)!.value)
  return { year: value("year"), month: value("month"), day: value("day") }
}

const index = (month: { year: number; month: number }) => month.year * 12 + month.month - 1
const baselineStarts = new Map<number, number>()
export function baselineStart(month: number): number {
  const cached = baselineStarts.get(month)
  if (cached !== undefined) return cached
  let low = Date.UTC(1800, 0, 1) / dayMs
  let high = Date.UTC(2250, 0, 1) / dayMs
  while (low < high) {
    const middle = Math.floor((low + high) / 2)
    if (index(hijri(new Date(middle * dayMs))) < month) low = middle + 1
    else high = middle
  }
  const result = hijri(new Date(low * dayMs))
  assert(index(result) === month && result.day === 1, "Unsupported Hijri month")
  baselineStarts.set(month, low)
  return low
}

function record(value: unknown): Record<string, unknown> {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), "Expected object")
  return value as Record<string, unknown>
}
function integer(value: unknown, min: number, max: number): number {
  assert(
    typeof value === "number" && Number.isInteger(value) && value >= min && value <= max,
    "Invalid integer"
  )
  return value
}
function text(value: unknown): string {
  assert(typeof value === "string" && value.trim().length > 0, "Invalid text")
  assert(
    [...value].every(character => {
      const code = character.codePointAt(0)!
      return (code >= 32 && code !== 127) || [9, 10, 13].includes(code)
    }),
    "Invalid control character"
  )
  return value
}
function monthIndex(value: unknown) {
  const row = record(value)
  return index({ year: integer(row.year, 1300, 1600), month: integer(row.month, 1, 12) })
}
function civilDay(value: unknown) {
  const row = record(value)
  const year = integer(row.year, 1, 9999),
    month = integer(row.month, 1, 12),
    day = integer(row.day, 1, 31)
  const date = new Date(0)
  date.setUTCFullYear(year, month - 1, day)
  assert(
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day,
    "Invalid civil date"
  )
  return date.getTime() / dayMs
}

// Keep month resolution aligned with Apple CalendarEngine.start(of:).
export function calendarStarts(input: unknown): (month: number) => number {
  const feed = record(input)
  assert(
    feed.schemaVersion === 1 &&
      Array.isArray(feed.announcements) &&
      feed.announcements.length <= 10000,
    "Invalid corrections feed"
  )
  const ids = new Set<string>(),
    anchors = new Map<number, number>()
  for (const value of feed.announcements) {
    const row = record(value),
      id = text(row.id),
      source = text(row.sourceID)
    assert(!ids.has(id), "Duplicate announcement ID")
    ids.add(id)
    integer(row.revision, 1, Number.MAX_SAFE_INTEGER)
    assert(
      ["nakedEye", "aidedSight", "government"].includes(String(row.method)),
      "Invalid sighting method"
    )
    const coverage = record(row.coverage)
    assert(
      Array.isArray(coverage.countries) && Array.isArray(coverage.polygons),
      "Invalid coverage"
    )
    assert(coverage.countries.length > 0 || coverage.polygons.length > 0, "Empty coverage")
    for (const country of coverage.countries)
      assert(
        typeof country === "string" && country.length === 2 && country === country.toUpperCase(),
        "Invalid country"
      )
    for (const polygon of coverage.polygons) {
      assert(Array.isArray(polygon) && polygon.length >= 3, "Invalid polygon")
      for (const point of polygon) {
        const p = record(point)
        assert(
          typeof p.latitude === "number" &&
            Number.isFinite(p.latitude) &&
            Math.abs(p.latitude) <= 90,
          "Invalid latitude"
        )
        assert(
          typeof p.longitude === "number" &&
            Number.isFinite(p.longitude) &&
            Math.abs(p.longitude) <= 180,
          "Invalid longitude"
        )
      }
    }
    const month = monthIndex(row.month),
      start = civilDay(row.start)
    assert(Math.abs(start - baselineStart(month)) <= 7, "Correction exceeds seven days")
    if (source !== "naked-eye-middle-east" || row.method !== "nakedEye") continue
    assert(!anchors.has(month) || anchors.get(month) === start, "Conflicting month confirmations")
    anchors.set(month, start)
  }
  const months = [...anchors.keys()].sort((a, b) => a - b)
  for (let i = 1; i < months.length; i++) {
    const left = months[i - 1]!,
      right = months[i]!,
      days = anchors.get(right)! - anchors.get(left)!
    assert(days >= 29 * (right - left) && days <= 30 * (right - left), "Conflicting month lengths")
  }
  const cache = new Map(anchors)
  return (month: number) => {
    const exact = cache.get(month)
    if (exact !== undefined) return exact
    const previous = months.findLast(value => value < month)
    const next = months.find(value => value > (previous ?? month))
    let result: number
    if (previous === undefined) {
      result = next === undefined ? baselineStart(month) : anchors.get(next)!
      if (next !== undefined)
        for (let cursor = next - 1; cursor >= month; cursor--) {
          const candidate = baselineStart(cursor),
            distance = result - candidate
          result =
            distance >= 29 && distance <= 30
              ? candidate
              : result - (baselineStart(cursor + 1) - candidate)
        }
    } else {
      result = anchors.get(previous)!
      for (let cursor = previous; cursor < month; cursor++) {
        let length = baselineStart(cursor + 1) - baselineStart(cursor)
        if (next !== undefined && cursor < next) {
          const remaining = next - cursor - 1,
            days = anchors.get(next)! - result
          length = Math.min(Math.max(length, days - 30 * remaining), days - 29 * remaining)
        } else {
          const distance = baselineStart(cursor + 1) - result
          if (distance >= 29 && distance <= 30) length = distance
        }
        result += length
      }
    }
    cache.set(month, result)
    return result
  }
}

function escapeText(value: string) {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/\r\n|\r|\n/g, "\\n")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
}
function fold(line: string) {
  let result = "",
    bytes = 0
  for (const character of line) {
    const size = Buffer.byteLength(character)
    if (bytes + size > 75) {
      result += "\r\n "
      bytes = 1
    }
    result += character
    bytes += size
  }
  return result
}
const dateValue = (day: number) =>
  new Date(day * dayMs).toISOString().slice(0, 10).replace(/-/g, "")

export function generateCalendar(
  events: unknown,
  feed: unknown,
  locale: Locale,
  now = new Date()
): string {
  assert(Array.isArray(events), "Invalid events")
  const ids = new Set<string>()
  const start = calendarStarts(feed)
  let currentMonth = index(hijri(now))
  const today = Math.floor(now.getTime() / dayMs)
  while (today < start(currentMonth)) currentMonth--
  while (today >= start(currentMonth + 1)) currentMonth++
  const currentYear = Math.floor(currentMonth / 12)
  const timestamp = now
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}/, "")
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Muntathir//Observances//EN",
    "CALSCALE:GREGORIAN",
    `X-WR-CALNAME:${locale === "ar" ? "منتظِر — المناسبات الإسلامية" : "Muntathir — Islamic observances"}`,
    "REFRESH-INTERVAL;VALUE=DURATION:PT12H",
    "X-PUBLISHED-TTL:PT12H",
  ]
  for (const value of events) {
    const event = record(value),
      id = text(event.id)
    assert(/^[a-z0-9-]+$/.test(id) && !ids.has(id), "Invalid or duplicate event ID")
    assert(
      Object.keys(event).every(key => ["id", "month", "day", "year", "title"].includes(key)),
      "Unexpected event field"
    )
    ids.add(id)
    const month = integer(event.month, 1, 12),
      day = integer(event.day, 1, 30)
    if (event.year !== undefined)
      integer(event.year, Number.MIN_SAFE_INTEGER, Number.MAX_SAFE_INTEGER)
    const titles = record(event.title)
    text(titles.en)
    for (const value of Object.values(titles)) text(value)
    const title = text(titles[locale] ?? titles.en)
    for (let year = currentYear - 1; year <= currentYear + 5; year++) {
      const occurrence = index({ year, month }),
        first = start(occurrence)
      if (day > start(occurrence + 1) - first) continue
      const date = first + day - 1
      const description =
        locale === "ar"
          ? `التاريخ الهجري: ${day}/${month}/${year} هـ. رؤية العين المجردة للشرق الأوسط؛ تقويم أم القرى عند غياب التأكيد. تصل تصحيحات التواريخ عند تحديث تطبيق التقويم للاشتراك.`
          : `Hijri date: ${day}/${month}/${year} AH. Middle East naked-eye confirmations; Umm al-Qura where unconfirmed. Date corrections arrive when your calendar app refreshes.`
      lines.push(
        "BEGIN:VEVENT",
        `UID:${id}-${year}-${locale}@muntathir.calendar`,
        `DTSTAMP:${timestamp}`,
        `LAST-MODIFIED:${timestamp}`,
        `DTSTART;VALUE=DATE:${dateValue(date)}`,
        `DTEND;VALUE=DATE:${dateValue(date + 1)}`,
        `SUMMARY:${escapeText(title)}`,
        `DESCRIPTION:${escapeText(description + (event.year === undefined ? "" : locale === "ar" ? `\nالسنة التاريخية: ${event.year} هـ` : `\nHistorical year: ${event.year} AH`))}`,
        "TRANSP:TRANSPARENT",
        "END:VEVENT"
      )
    }
  }
  lines.push("END:VCALENDAR")
  return lines.map(fold).join("\r\n") + "\r\n"
}
