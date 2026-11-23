import { useState } from 'preact/hooks'
import type { Locale } from '../core/i18n.ts'
import { canOpenLocationSettings, locate } from './location.ts'
import { deviceZone, useApp } from './state.ts'
import { webApp } from './telegram.ts'
import { External, Header } from './ui.tsx'

export function LocationForm({ onSaved }: { onSaved?: () => void }) {
  const { t, setPlace } = useApp()
  const [state, setState] = useState<'ready' | 'locating' | 'denied'>('ready')

  async function find() {
    setState('locating')
    const found = await locate()
    if (!found) return setState('denied')
    setState('ready')
    setPlace({ ...found, zone: deviceZone() })
    onSaved?.()
  }

  return (
    <div class="location">
      <p class="muted">{t.locationPrivate}</p>
      <div class="actions">
        <button class="button primary" disabled={state === 'locating'} onClick={find}>
          {state === 'locating' ? t.loading : t.useLocation}
        </button>
      </div>
      {state === 'denied' && (
        <div role="alert">
          <p>{t.locationDenied}</p>
          {canOpenLocationSettings() && (
            <button class="button" onClick={() => webApp!.LocationManager.openSettings()}>
              {t.openSettings}
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export function Settings() {
  const { t, locale, setLocale, place, setPlace } = useApp()
  const [changing, setChanging] = useState(false)
  const privacy = `https://xn--pgbou4cf.com${locale === 'ar' ? '' : '/en'}/privacy/`
  return (
    <>
      <Header title={t.settings} />
      <section class="card">
        <label>
          {t.language}
          <select value={locale} onChange={event => setLocale(event.currentTarget.value as Locale)}>
            <option value="ar">العربية</option>
            <option value="en">English</option>
          </select>
        </label>
      </section>
      <section class="card">
        <h2>{t.location}</h2>
        {place && !changing ? (
          <>
            <p class="number"><bdi>{place.latitude.toFixed(3)}, {place.longitude.toFixed(3)}</bdi></p>
            <div class="actions">
              <button class="button" onClick={() => setChanging(true)}>{t.changeLocation}</button>
              <button class="button" onClick={() => setPlace(null)}>{t.remove}</button>
            </div>
          </>
        ) : (
          <LocationForm onSaved={() => setChanging(false)} />
        )}
      </section>
      <section class="card">
        <p><External url={privacy}>{t.privacy}</External></p>
        <p><External url={`${location.origin}/licenses.txt`}>Open source licenses</External></p>
      </section>
    </>
  )
}
