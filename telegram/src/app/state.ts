import { createContext } from 'preact'
import { useContext, useEffect, useState } from 'preact/hooks'
import type { Locale, strings } from '../core/i18n.ts'
import type { Place } from '../core/prayer.ts'
import type { Bootstrap } from '../core/types.ts'
import type { Route, Tab } from './routes.ts'

/** The zone is the device's when the fix was taken, as on iOS. */
export type SavedPlace = Place & { zone: string }

export type App = {
  data: Bootstrap
  locale: Locale
  t: (typeof strings)[Locale]
  setLocale: (locale: Locale) => void
  place: SavedPlace | null
  setPlace: (place: SavedPlace | null) => void
  push: (route: Route) => void
  pop: () => void
  select: (tab: Tab) => void
}

export const AppContext = createContext<App>(null as never)
export const useApp = () => useContext(AppContext)
export const deviceZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'

export function useNow(interval: number): number {
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const update = () => setNow(Date.now())
    const timer = setInterval(update, interval)
    document.addEventListener('visibilitychange', update)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', update)
    }
  }, [interval])
  return now
}
