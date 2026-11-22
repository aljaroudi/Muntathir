import { render, type JSX } from 'preact'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'
import { isZone } from '../core/day.ts'
import { localeOf, strings, type Locale } from '../core/i18n.ts'
import { DEFAULT_METHOD, isMethod, validPlace, type Method } from '../core/prayer.ts'
import type { Bootstrap } from '../core/types.ts'
import { useGet } from './api.ts'
import { Calendar } from './calendar.tsx'
import * as library from './library.tsx'
import { Qibla } from './qibla.tsx'
import { launch, TABS, type Route, type Tab } from './routes.ts'
import { Search } from './search.tsx'
import { Settings } from './settings.tsx'
import { AppContext, type App, type SavedPlace } from './state.ts'
import { cloud, device, haptic, initData, supports, webApp } from './telegram.ts'
import { Today } from './today.tsx'

type Saved = { locale: Locale; method: Method; place: SavedPlace | null }

const KEYS = { locale: 'language', method: 'method', place: 'location' }
const userLocale = localeOf(webApp?.initDataUnsafe.user?.language_code ?? navigator.language)
const initial = launch(
  new URLSearchParams(location.search).get('open') ?? webApp?.initDataUnsafe.start_param ?? '',
)

function setDocument(locale: Locale) {
  document.documentElement.lang = locale
  document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr'
  document.title = strings[locale].name
}

async function loadSaved(): Promise<Saved> {
  const [locale, method, place] = await Promise.all([
    cloud.get<Locale>(KEYS.locale),
    cloud.get<Method>(KEYS.method),
    device.get<SavedPlace>(KEYS.place),
    library.loadPosition(),
  ])
  return {
    locale: locale === 'ar' || locale === 'en' ? locale : userLocale,
    method: isMethod(method) ? method : DEFAULT_METHOD,
    place: place && validPlace(place) && isZone(place.zone) ? place : null,
  }
}

const ICONS: Record<Tab, JSX.Element> = {
  today: <><circle cx="12" cy="12" r="4" /><path d="M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4m0-12.8L17 7M7 17l-1.4 1.4" /></>,
  calendar: <><rect x="4" y="5" width="16" height="15" rx="3" /><path d="M4 10h16M9 3v4m6-4v4" /></>,
  qibla: <><circle cx="12" cy="12" r="9" /><path d="m15.5 8.5-2 5-5 2 2-5Z" /></>,
  library: <path d="M12 7c-3-2.5-6-2.5-8-1.5v13c2-1 5-1 8 1.5 3-2.5 6-2.5 8-1.5v-13c-2-1-5-1-8 1.5Zm0 0v13" />,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4.5 4.5" /></>,
}

function Page({ route }: { route: Route }) {
  switch (route.page) {
    case 'settings': return <Settings />
    case 'quran': return <library.Quran />
    case 'surah': return <library.Surah number={route.number} verse={route.verse} />
    case 'verse': return <library.VersePage id={route.id} />
    case 'hadith': return <library.Collections />
    case 'collection': return <library.Collection id={route.id} />
    case 'chapter': return <library.Chapter id={route.id} />
    case 'narration': return <library.Narration id={route.id} />
    case 'supplications': return <library.Supplications />
    case 'supplication': return <library.SupplicationPage id={route.id} />
    case 'authorities': return <library.Authorities />
    case 'contents': return <library.RulingContents authority={route.authority} language={route.language} />
    case 'topic': return <library.TopicPage id={route.id} />
    case 'ruling': return <library.RulingPage id={route.id} />
  }
}

const ROOTS: Record<Tab, () => JSX.Element> = {
  today: Today,
  calendar: Calendar,
  qibla: Qibla,
  library: library.Library,
  search: Search,
}

function Shell({ data, saved }: { data: Bootstrap; saved: Saved }) {
  const [locale, setLocale] = useState(saved.locale)
  const [method, setMethod] = useState(saved.method)
  const [place, setPlace] = useState(saved.place)
  const [tab, setTab] = useState<Tab>(initial.tab)
  const [stack, setStack] = useState<Route[]>(initial.route ? [initial.route] : [])
  const offsets = useRef<number[]>([])
  const restore = useRef<number | null>(null)

  const app = useMemo<App>(
    () => ({
      data,
      locale,
      t: strings[locale],
      setLocale(value) {
        setLocale(value)
        cloud.set(KEYS.locale, value)
      },
      method,
      setMethod(value) {
        setMethod(value)
        cloud.set(KEYS.method, value)
      },
      place,
      setPlace(value) {
        setPlace(value)
        if (value) device.set(KEYS.place, value)
        else device.remove(KEYS.place)
      },
      push(route) {
        offsets.current.push(window.scrollY)
        restore.current = 0
        setStack(routes => [...routes, route])
      },
      pop() {
        restore.current = offsets.current.pop() ?? 0
        setStack(routes => routes.slice(0, -1))
      },
      select(value) {
        haptic('selection')
        offsets.current = []
        restore.current = 0
        setStack([])
        setTab(value)
      },
    }),
    [data, locale, method, place],
  )

  useLayoutEffect(() => setDocument(locale), [locale])
  useLayoutEffect(() => {
    if (restore.current !== null) window.scrollTo(0, restore.current)
    restore.current = null
  }, [stack, tab])

  const nested = stack.length > 0
  const nativeBack = supports('6.1')
  useEffect(() => {
    if (!nativeBack || !nested) return
    const button = webApp!.BackButton
    button.onClick(app.pop)
    button.show()
    return () => {
      button.offClick(app.pop)
      button.hide()
    }
  }, [nativeBack, nested, app])

  const route = stack.at(-1)
  const Root = ROOTS[tab]
  return (
    <AppContext.Provider value={app}>
      <main>
        {nested && !nativeBack && <button class="link" onClick={app.pop}>{app.t.back}</button>}
        {route ? <Page key={JSON.stringify(route)} route={route} /> : <Root key={tab} />}
      </main>
      <nav class="tabs" aria-label={app.t.name}>
        {TABS.map(value => (
          <button key={value} aria-current={tab === value ? 'page' : undefined} onClick={() => app.select(value)}>
            <svg viewBox="0 0 24 24" aria-hidden="true">{ICONS[value]}</svg>
            <span>{app.t[value]}</span>
          </button>
        ))}
      </nav>
    </AppContext.Provider>
  )
}

function Root() {
  const t = strings[userLocale]
  const bootstrap = useGet<Bootstrap>(initData ? 'bootstrap' : null)
  const [saved, setSaved] = useState<Saved>()
  useEffect(() => {
    if (initData) void loadSaved().then(setSaved)
  }, [])
  if (!initData) return <main class="status"><h1>{t.name}</h1><p>{t.outside}</p></main>
  if (bootstrap.failure)
    return (
      <main class="status" role="alert">
        <p>{bootstrap.failure === 'expired' ? t.reopen : t.failed}</p>
        {bootstrap.failure === 'failed' && <button class="button" onClick={bootstrap.retry}>{t.retry}</button>}
      </main>
    )
  if (!bootstrap.data || !saved) return <main class="status" role="status">{t.loading}</main>
  return <Shell data={bootstrap.data} saved={saved} />
}

function applyTheme() {
  if (webApp && initData) document.documentElement.dataset.scheme = webApp.colorScheme
}

setDocument(userLocale)
applyTheme()
if (webApp && initData) {
  webApp.onEvent('themeChanged', applyTheme)
  if (supports('6.1')) {
    webApp.setHeaderColor('secondary_bg_color')
    webApp.setBackgroundColor('secondary_bg_color')
  }
  webApp.ready()
  webApp.expand()
}
render(<Root />, document.getElementById('app')!)
