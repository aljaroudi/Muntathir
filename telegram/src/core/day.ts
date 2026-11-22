import umm from '../../../shared/ummalqura.json'

const DAY_MS = 86_400_000

/** A civil date as whole days since 1970-01-01, independent of any time zone. */
export type Day = number

export function day(year: number, month: number, date: number): Day {
  return Date.UTC(year, month - 1, date) / DAY_MS
}

export function civil(value: Day) {
  const date = new Date(value * DAY_MS)
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, date: date.getUTCDate() }
}

export function isZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: zone })
    return zone !== ''
  } catch {
    return false
  }
}

const formatters = new Map<string, Intl.DateTimeFormat>()

/** The civil date containing [instant] in [zone]. */
export function dayIn(instant: number, zone: string): Day {
  let format = formatters.get(zone)
  if (!format) {
    format = new Intl.DateTimeFormat('en-u-ca-gregory-nu-latn', {
      timeZone: zone,
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
    })
    formatters.set(zone, format)
  }
  const part = { year: 0, month: 0, day: 0 }
  for (const { type, value } of format.formatToParts(instant))
    if (type === 'year' || type === 'month' || type === 'day') part[type] = Number(value)
  return day(part.year, part.month, part.day)
}

export type HijriDate = { year: number; month: number; date: number }

export const monthIndex = (year: number, month: number) => year * 12 + month - 1

/** Consecutive month starts: `starts[i]` is the first day of month index `first + i`. */
export type Months = { first: number; starts: Day[] }

export function hijri(months: Months, value: Day): HijriDate | null {
  const { first, starts } = months
  if (starts.length < 2 || value < starts[0]! || value >= starts[starts.length - 1]!) return null
  let low = 0
  let high = starts.length - 1
  while (high - low > 1) {
    const middle = (low + high) >> 1
    if (starts[middle]! <= value) low = middle
    else high = middle
  }
  const index = first + low
  return { year: Math.floor(index / 12), month: (index % 12) + 1, date: value - starts[low]! + 1 }
}

/** Uncorrected Umm al-Qura, the apps' baseline. The table ships because WebView ICU varies. */
export const baseline: Months = (() => {
  const [year, month, date] = umm.start.split('-').map(Number) as [number, number, number]
  const starts = [day(year, month, date)]
  for (const length of umm.lengths) starts.push(starts.at(-1)! + (length === '0' ? 30 : 29))
  return { first: monthIndex(umm.first.year, umm.first.month), starts }
})()
