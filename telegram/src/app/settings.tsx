import { useState } from 'preact/hooks'
import { isZone } from '../core/day.ts'
import { METHOD_NAMES, type Locale } from '../core/i18n.ts'
import { METHODS, validPlace, type Method } from '../core/prayer.ts'
import { canOpenLocationSettings, locate } from './location.ts'
import { deviceZone, useApp } from './state.ts'
import { webApp } from './telegram.ts'
import { External, Header } from './ui.tsx'

function zones(): string[] {
  try {
    return Intl.supportedValuesOf('timeZone')
  } catch {
    return []
  }
}

export function LocationForm({ onSaved }: { onSaved?: () => void }) {
  const { t, setPlace } = useApp()
  const [state, setState] = useState<'ready' | 'locating' | 'denied'>('ready')
  const [manual, setManual] = useState(false)
  const [invalid, setInvalid] = useState(false)

  async function find() {
    setState('locating')
    const found = await locate()
    if (!found) {
      setState('denied')
      setManual(true)
      return
    }
    setState('ready')
    setPlace({ ...found, zone: deviceZone() })
    onSaved?.()
  }

  function save(event: Event) {
    event.preventDefault()
    const form = new FormData(event.currentTarget as HTMLFormElement)
    const field = (name: string) => String(form.get(name) ?? '').trim()
    // Accept Arabic digits and a decimal comma.
    const number = (name: string) => {
      const value = field(name)
        .replace(/[٠-٩]/g, digit => String(digit.charCodeAt(0) - 0x660))
        .replace(/[٫,]/g, '.')
      return value ? Number(value) : NaN
    }
    const place = { latitude: number('latitude'), longitude: number('longitude') }
    const zone = field('zone')
    const valid = validPlace(place) && isZone(zone)
    setInvalid(!valid)
    if (!valid) return
    setPlace({ ...place, zone })
    onSaved?.()
  }

  return (
    <div class="location">
      <p class="muted">{t.locationPrivate}</p>
      <div class="actions">
        <button class="button primary" disabled={state === 'locating'} onClick={find}>
          {state === 'locating' ? t.loading : t.useLocation}
        </button>
        {!manual && <button class="button" onClick={() => setManual(true)}>{t.manual}</button>}
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
      {manual && (
        // Submission is handled here: the CSP blocks real form posts.
        <form onSubmit={save} noValidate>
          <label>{t.latitude}<input name="latitude" dir="ltr" inputMode="text" autocomplete="off" required /></label>
          <label>{t.longitude}<input name="longitude" dir="ltr" inputMode="text" autocomplete="off" required /></label>
          {/* The device zone is right for a GPS fix, not for typed coordinates. */}
          <label>
            {t.timeZone}
            <input name="zone" dir="ltr" list="time-zones" defaultValue={deviceZone()} autocomplete="off" required />
          </label>
          <datalist id="time-zones">{zones().map(zone => <option key={zone} value={zone} />)}</datalist>
          {invalid && <p role="alert">{t.invalidLocation}</p>}
          <button class="button primary" type="submit">{t.save}</button>
        </form>
      )}
    </div>
  )
}

export function Settings() {
  const { t, locale, setLocale, method, setMethod, place, setPlace } = useApp()
  const [changing, setChanging] = useState(false)
  const privacy = `https://xn--pgbou4cf.com${locale === 'ar' ? '' : '/en'}/privacy/`
  return (
    <>
      <Header title={t.settings} />
      <section class="card">
        <label>
          {t.method}
          <select value={method} onChange={event => setMethod(event.currentTarget.value as Method)}>
            {METHODS.map(value => <option key={value} value={value}>{METHOD_NAMES[locale][value]}</option>)}
          </select>
        </label>
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
            <p class="muted"><bdi>{place.zone}</bdi></p>
            <div class="actions">
              <button class="button" onClick={() => setChanging(true)}>{t.changeLocation}</button>
              <button class="button" onClick={() => setPlace(null)}>{t.remove}</button>
            </div>
          </>
        ) : (
          <LocationForm onSaved={() => setChanging(false)} />
        )}
      </section>
      <section class="card credits">
        <h2>{t.credits}</h2>
        <p>
          <External url="https://tanzil.net/">{t.quranCredit}</External>
          {' · '}
          <External url="https://creativecommons.org/licenses/by/3.0/">CC BY 3.0</External>
        </p>
        <p><External url="https://tanzil.net/trans/en.qarai">{t.translationCredit}</External></p>
        <p><External url="https://thaqalayn.net/">Thaqalayn</External></p>
        <p><External url="https://github.com/OpenITI">OpenITI</External></p>
        <p><External url="https://www.duas.org/">Duas.org</External></p>
        <p><External url="https://github.com/batoulapps/adhan-js">Adhan (MIT)</External></p>
        <p><External url={`${location.origin}/licenses.txt`}>Open source licenses</External></p>
        <p><External url={privacy}>{t.privacy}</External></p>
      </section>
    </>
  )
}
