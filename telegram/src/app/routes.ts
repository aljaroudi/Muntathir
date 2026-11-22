export const TABS = ['today', 'calendar', 'qibla', 'library', 'search'] as const
export type Tab = (typeof TABS)[number]

export type Route =
  | { page: 'settings' }
  | { page: 'quran' }
  | { page: 'surah'; number: number; verse?: number }
  | { page: 'verse'; id: string }
  | { page: 'hadith' }
  | { page: 'collection'; id: string }
  | { page: 'chapter'; id: string }
  | { page: 'narration'; id: string }
  | { page: 'supplications' }
  | { page: 'supplication'; id: string }
  | { page: 'authorities' }
  | { page: 'contents'; authority: string; language: string }
  | { page: 'topic'; id: string }
  | { page: 'ruling'; id: string }

// The letters of server/ids.ts.
const PAGES = {
  q: 'verse',
  h: 'narration',
  i: 'narration',
  d: 'supplication',
  r: 'ruling',
  c: 'chapter',
  t: 'topic',
} as const

export function routeFor(id: string): Route | null {
  if (!/^[qhdrcti][A-Za-z0-9_-]{16}$/.test(id)) return null
  return { page: PAGES[id[0] as keyof typeof PAGES], id }
}

/** `?open=` from chat buttons, or `startapp` from shared links. */
export function launch(value: string): { tab: Tab; route: Route | null } {
  const tab = TABS.find(item => item === value)
  if (tab) return { tab, route: null }
  const route = routeFor(value)
  return { tab: route ? 'library' : 'today', route }
}
