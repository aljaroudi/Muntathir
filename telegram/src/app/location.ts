import { validPlace, type Place } from '../core/prayer.ts'
import { supports, webApp } from './telegram.ts'

const LOCATION_TIMEOUT_MS = 20_000

function fromTelegram(): Promise<Place | null> {
  return new Promise(resolve => {
    if (!webApp || !supports('8.0')) return resolve(null)
    const manager = webApp.LocationManager
    const timer = setTimeout(() => resolve(null), LOCATION_TIMEOUT_MS)
    const finish = (place: Place | null) => {
      clearTimeout(timer)
      resolve(place)
    }
    const request = () => {
      // getLocation throws when the device has no location.
      if (!manager.isLocationAvailable) return finish(null)
      manager.getLocation(value =>
        finish(value ? { latitude: value.latitude, longitude: value.longitude } : null),
      )
    }
    if (manager.isInited) request()
    else manager.init(request)
  })
}

function fromBrowser(): Promise<Place | null> {
  return new Promise(resolve => {
    if (!navigator.geolocation) return resolve(null)
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => resolve({ latitude: coords.latitude, longitude: coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: false, timeout: LOCATION_TIMEOUT_MS, maximumAge: 300_000 },
    )
  })
}

/** The fix stays in the app: prayer times and Qibla are calculated here, not on the server. */
export async function locate(): Promise<Place | null> {
  const place = (await fromTelegram()) ?? (await fromBrowser())
  return place && validPlace(place) ? place : null
}

export function canOpenLocationSettings(): boolean {
  if (!webApp || !supports('8.0')) return false
  const manager = webApp.LocationManager
  return manager.isInited && manager.isLocationAvailable && manager.isAccessRequested && !manager.isAccessGranted
}
