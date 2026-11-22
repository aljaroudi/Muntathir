import {
  CalculationMethod,
  Coordinates,
  HighLatitudeRule,
  Madhab,
  PolarCircleResolution,
  PrayerTimes,
  Qibla,
  type CalculationParameters,
} from 'adhan'
import { baseline, civil, hijri, type Day } from './day.ts'

// Mirrors PrayerCalculator.swift / PrayerCalculator.kt; test/prayer-vectors.csv pins parity.
export const METHODS = ['tehran', 'jafari', 'ummAlQura'] as const
export type Method = (typeof METHODS)[number]
export const DEFAULT_METHOD: Method = 'tehran'
export const isMethod = (value: unknown): value is Method => METHODS.includes(value as Method)

export const TIMES = [
  'imsak',
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'sunset',
  'maghrib',
  'isha',
  'midnight',
] as const
export type TimeName = (typeof TIMES)[number]
export const PRAYERS: readonly TimeName[] = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']
export type Moment = { name: TimeName; at: number }
export type Place = { latitude: number; longitude: number }

const IMSAK_MINUTES = 10
const MINUTE = 60_000

export function validPlace({ latitude, longitude }: Place): boolean {
  return (
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    Math.abs(latitude) <= 90 &&
    Math.abs(longitude) <= 180
  )
}

function parameters(method: Method, place: Coordinates, value: Day): CalculationParameters {
  const result =
    method === 'tehran'
      ? CalculationMethod.Tehran()
      : method === 'jafari'
        ? CalculationMethod.Other()
        : CalculationMethod.UmmAlQura()
  if (method === 'jafari') {
    result.fajrAngle = 16
    result.maghribAngle = 4
    result.ishaAngle = 14
  }
  result.madhab = Madhab.Shafi
  // adhan-js always defaults to middle of the night; the apps use the recommended rule.
  result.highLatitudeRule = HighLatitudeRule.recommended(place)
  result.polarCircleResolution = PolarCircleResolution.Unresolved
  // The preset's Ramadan interval follows the calculated calendar, not sighting corrections.
  if (method === 'ummAlQura' && hijri(baseline, value)?.month === 9) result.ishaInterval += 30
  return result
}

/** adhan-js reads local getters, so a day is passed as local noon. */
function localNoon(value: Day): Date {
  const { year, month, date } = civil(value)
  return new Date(year, month - 1, date, 12)
}

function calculate(place: Coordinates, value: Day, params: CalculationParameters) {
  const times = new PrayerTimes(place, localNoon(value), params)
  const all = [times.fajr, times.sunrise, times.dhuhr, times.asr, times.sunset, times.maghrib, times.isha]
  return all.every(time => Number.isFinite(time.getTime())) ? times : null
}

/** Adhan Swift also fails when the following day has no sunrise or sunset. */
function hasSun(place: Coordinates, value: Day, params: CalculationParameters) {
  const times = new PrayerTimes(place, localNoon(value), params)
  return Number.isFinite(times.sunrise.getTime()) && Number.isFinite(times.sunset.getTime())
}

// adhan-js keeps fractional seconds when a night-portion rule applies.
const minute = (time: Date) => Math.floor(time.getTime() / MINUTE) * MINUTE

/** Empty when the times can't be calculated at this latitude and date. */
export function prayerTimes(place: Place, value: Day, method: Method): Moment[] {
  if (!validPlace(place)) return []
  const coordinates = new Coordinates(place.latitude, place.longitude)
  const params = parameters(method, coordinates, value)
  const times = calculate(coordinates, value, params)
  if (!times || !hasSun(coordinates, value + 1, params)) return []
  // adhan silently falls back to sunset when the Maghrib angle is unreachable.
  if (method !== 'ummAlQura' && minute(times.maghrib) <= minute(times.sunset)) return []
  const fajr = minute(times.fajr)
  const sunset = minute(times.sunset)
  const result: Moment[] = [
    { name: 'imsak', at: fajr - IMSAK_MINUTES * MINUTE },
    { name: 'fajr', at: fajr },
    { name: 'sunrise', at: minute(times.sunrise) },
    { name: 'dhuhr', at: minute(times.dhuhr) },
    { name: 'asr', at: minute(times.asr) },
    { name: 'sunset', at: sunset },
    { name: 'maghrib', at: minute(times.maghrib) },
    { name: 'isha', at: minute(times.isha) },
  ]
  // As in the apps, tomorrow's Fajr keeps today's parameters.
  const next = calculate(coordinates, value + 1, params)
  if (next && hasSun(coordinates, value + 2, params)) {
    const middle = sunset + (minute(next.fajr) - sunset) / 2
    result.push({ name: 'midnight', at: Math.round(middle / MINUTE) * MINUTE })
  }
  return result
}

export function nextPrayer(place: Place, today: Day, method: Method, now: number): Moment | null {
  for (const value of [today, today + 1]) {
    const found = prayerTimes(place, value, method).find(
      moment => moment.at > now && PRAYERS.includes(moment.name),
    )
    if (found) return found
  }
  return null
}

/** Sunset for religious-day rollover: always from a Jafari calculation, as in the apps. */
export function religiousSunset(place: Place, value: Day): number | null {
  return prayerTimes(place, value, 'jafari').find(moment => moment.name === 'sunset')?.at ?? null
}

/** Degrees clockwise from true north. */
export function qibla(place: Place): number {
  return Qibla(new Coordinates(place.latitude, place.longitude))
}
