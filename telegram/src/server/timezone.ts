import { find } from 'geo-tz'
import { isZone } from '../core/day.ts'
import type { Place } from '../core/prayer.ts'

/** The time zone at a place, found offline. */
export function zoneAt({ latitude, longitude }: Place): string {
  return find(latitude, longitude).find(isZone) ?? 'UTC'
}
