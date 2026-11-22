import geomagnetism from 'geomagnetism'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'
import { androidHeading, headingError, isAligned, trueHeading, webkitHeading } from '../core/compass.ts'
import { qibla } from '../core/prayer.ts'
import { LocationForm } from './settings.tsx'
import { useApp } from './state.ts'
import { haptic, supports, webApp } from './telegram.ts'
import { Header } from './ui.tsx'

type Compass = 'idle' | 'on' | 'none'
type WebKitEvent = DeviceOrientationEvent & { webkitCompassHeading?: number; webkitCompassAccuracy?: number }
type Permission = { requestPermission?: () => Promise<'granted' | 'denied'> }

/** See core/compass.ts for why each platform differs. */
function source(): 'telegram' | 'webkit' | null {
  if (webApp?.platform === 'android' && supports('8.0')) return 'telegram'
  if (webApp?.platform === 'ios' && 'DeviceOrientationEvent' in window) return 'webkit'
  return null
}

/** If no heading arrives in this long, there's no compass. */
const FIRST_READING_MS = 6000

function useMagneticHeading() {
  const kind = source()
  const [compass, setCompass] = useState<Compass>(kind ? 'idle' : 'none')
  const [heading, setHeading] = useState<number | null>(null)

  useEffect(() => {
    if (compass !== 'on') return
    let seen = false
    const timer = setTimeout(() => {
      if (!seen) setCompass('none')
    }, FIRST_READING_MS)

    if (kind === 'telegram') {
      const sensor = webApp!.DeviceOrientation
      const changed = () => {
        seen ||= sensor.absolute
        setHeading(androidHeading(sensor))
      }
      webApp!.onEvent('deviceOrientationChanged', changed)
      sensor.start({ need_absolute: true, refresh_rate: 100 }, started => {
        if (!started) setCompass('none')
      })
      return () => {
        clearTimeout(timer)
        webApp!.offEvent('deviceOrientationChanged', changed)
        sensor.stop()
      }
    }

    const changed = (event: WebKitEvent) => {
      seen ||= typeof event.webkitCompassHeading === 'number'
      setHeading(webkitHeading(event.webkitCompassHeading, event.webkitCompassAccuracy))
    }
    window.addEventListener('deviceorientation', changed)
    return () => {
      clearTimeout(timer)
      window.removeEventListener('deviceorientation', changed)
    }
  }, [compass, kind])

  // iOS only grants motion access from a tap.
  async function start() {
    const request = (window.DeviceOrientationEvent as unknown as Permission | undefined)?.requestPermission
    try {
      if (kind === 'webkit' && request) {
        const answer = await request.call(window.DeviceOrientationEvent)
        if (answer !== 'granted') return setCompass('none')
      }
      setCompass('on')
    } catch {
      setCompass('none')
    }
  }

  return { compass, heading, start }
}

export function Qibla() {
  const { t, place } = useApp()
  const { compass, heading, start } = useMagneticHeading()
  const declination = useMemo(
    () =>
      place
        ? geomagnetism
            .model(new Date(), { allowOutOfBoundsModel: true })
            .point([place.latitude, place.longitude]).decl
        : 0,
    [place],
  )
  const bearing = place ? qibla(place) : 0
  const facing = compass === 'on' && heading !== null ? trueHeading(heading, declination) : null
  const error = place && facing !== null ? headingError(bearing, facing) : null
  const previous = useRef(false)
  const aligned = error !== null && isAligned(error, previous.current)

  useEffect(() => {
    if (aligned && !previous.current) haptic('success')
    previous.current = aligned
  }, [aligned])

  if (!place)
    return (
      <>
        <Header title={t.qibla} />
        <section class="card"><LocationForm /></section>
      </>
    )

  const rotation = -(facing ?? 0)
  return (
    <>
      <Header title={t.qibla} subtitle={`${bearing.toFixed(1)}° ${t.fromNorth}`} />
      <svg class={`dial${aligned ? ' aligned' : ''}`} viewBox="-120 -120 240 240" role="img" aria-label={`${t.qibla} ${bearing.toFixed(0)}°`}>
        <g transform={`rotate(${rotation})`}>
          <circle class="dial-ring" r="100" />
          {Array.from({ length: 24 }, (_, index) => (
            <path key={index} class="dial-tick" d={index % 6 ? 'M0-100v7' : 'M0-100v14'} transform={`rotate(${index * 15})`} />
          ))}
          <g transform="translate(0 -70)">
            <text class="dial-north" transform={`rotate(${-rotation})`} dy="6">N</text>
          </g>
          <g transform={`rotate(${bearing})`}>
            <path class="dial-needle" d="M0-96 13-64H4V28H-4V-64h-9Z" />
          </g>
        </g>
        <circle class="dial-center" r="7" />
        {facing !== null && <path class="dial-mark" d="M-7-118H7L0-105Z" />}
      </svg>
      <div class="status" aria-live="polite">
        {compass === 'none' && <p>{t.compassUnavailable}</p>}
        {compass === 'idle' && <button class="button primary" onClick={start}>{t.compassStart}</button>}
        {compass === 'on' && (
          <p class="direction">
            {error === null ? t.compassHint : aligned ? t.aligned : error > 0 ? t.turnRight : t.turnLeft}
          </p>
        )}
      </div>
    </>
  )
}
