/** The parts of Telegram.WebApp this app uses. https://core.telegram.org/bots/webapps */
type Callback<T> = (error: unknown, value?: T) => void
type Storage = {
  getItem(key: string, callback: Callback<string | null>): void
  setItem(key: string, value: string, callback?: Callback<boolean>): void
  removeItem(key: string, callback?: Callback<boolean>): void
}
type WebApp = {
  initData: string
  initDataUnsafe: { start_param?: string; user?: { language_code?: string } }
  platform: string
  colorScheme: 'light' | 'dark'
  ready(): void
  expand(): void
  isVersionAtLeast(version: string): boolean
  onEvent(event: string, handler: () => void): void
  offEvent(event: string, handler: () => void): void
  setHeaderColor(color: string): void
  setBackgroundColor(color: string): void
  openLink(url: string): void
  openTelegramLink(url: string): void
  BackButton: { show(): void; hide(): void; onClick(handler: () => void): void; offClick(handler: () => void): void }
  HapticFeedback: { notificationOccurred(type: 'success'): void; selectionChanged(): void }
  CloudStorage: Storage
  DeviceStorage: Storage
  LocationManager: {
    isInited: boolean
    isLocationAvailable: boolean
    isAccessRequested: boolean
    isAccessGranted: boolean
    init(callback?: () => void): void
    getLocation(callback: (value: { latitude: number; longitude: number } | null) => void): void
    openSettings(): void
  }
  DeviceOrientation: {
    absolute: boolean
    alpha: number | null
    beta: number | null
    gamma: number | null
    start(params: { need_absolute: boolean; refresh_rate: number }, callback?: (ok: boolean) => void): void
    stop(): void
  }
}

declare global {
  interface Window {
    Telegram?: { WebApp?: WebApp }
  }
}

export const webApp = window.Telegram?.WebApp
/** Outside Telegram the SDK still loads, with empty initData. */
export const initData = webApp?.initData ?? ''
export const supports = (version: string) => webApp?.isVersionAtLeast(version) === true

const STORAGE_TIMEOUT_MS = 1500

function local<T>(action: (storage: globalThis.Storage) => T): T | null {
  try {
    return action(localStorage)
  } catch {
    return null
  }
}

/**
 * A Telegram store, mirrored in localStorage for clients without one or that answer slowly.
 * [late] receives an answer that arrived after the mirror was used.
 */
function store(minimum: string, select: (app: WebApp) => Storage) {
  const native = () => (webApp && supports(minimum) ? select(webApp) : null)
  // A late answer mustn't undo a change made since the read.
  const changed = new Set<string>()
  const parse = <T>(raw: string | null | undefined): T | null => {
    try {
      return raw ? (JSON.parse(raw) as T) : null
    } catch {
      return null
    }
  }
  const mirrored = (key: string) => local(storage => storage.getItem(key))
  const mirror = (key: string, raw: string) => local(storage => storage.setItem(key, raw))

  return {
    get<T>(key: string, late?: (value: T) => void): Promise<T | null> {
      return new Promise(resolve => {
        const fallback = () => resolve(parse<T>(mirrored(key)))
        const storage = native()
        if (!storage) return fallback()
        let timedOut = false
        const timer = setTimeout(() => {
          timedOut = true
          fallback()
        }, STORAGE_TIMEOUT_MS)
        try {
          storage.getItem(key, (error, raw) => {
            clearTimeout(timer)
            if (changed.has(key)) return fallback()
            const value = error ? null : parse<T>(raw)
            if (value === null) return fallback()
            mirror(key, raw!)
            if (timedOut) late?.(value)
            else resolve(value)
          })
        } catch {
          clearTimeout(timer)
          fallback()
        }
      })
    },
    set(key: string, value: unknown) {
      const raw = JSON.stringify(value)
      changed.add(key)
      mirror(key, raw)
      try {
        native()?.setItem(key, raw)
      } catch {
        // The mirror has it.
      }
    },
    remove(key: string) {
      changed.add(key)
      local(storage => storage.removeItem(key))
      try {
        native()?.removeItem(key)
      } catch {
        // Nothing is stored there.
      }
    },
  }
}

/** Location and reading position: never leave the device. */
export const device = store('9.0', app => app.DeviceStorage)
/** Method and language: follow the user's Telegram account. */
export const cloud = store('6.9', app => app.CloudStorage)

export function openLink(url: string) {
  if (webApp) webApp.openLink(url)
  else window.open(url, '_blank', 'noopener,noreferrer')
}

export function openTelegramLink(url: string) {
  if (webApp) webApp.openTelegramLink(url)
  else window.open(url, '_blank', 'noopener,noreferrer')
}

export function haptic(kind: 'success' | 'selection') {
  if (!supports('6.1')) return
  if (kind === 'success') webApp!.HapticFeedback.notificationOccurred('success')
  else webApp!.HapticFeedback.selectionChanged()
}
