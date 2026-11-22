// Telegram's DeviceOrientation.alpha means different things per client, so each platform has its own
// rule (read from the clients' sources, November 2026):
// - Android (BotSensors.java): alpha = -azimuth of the top of the phone, from magnetic north.
// - iOS (WebAppController.swift): alpha = CMDeviceMotion.heading, clockwise, from true *or* magnetic
//   north depending on a permission the app can't see, with an undocumented zero axis. WebKit's
//   webkitCompassHeading is used instead: documented, magnetic, and it reports its accuracy.
// - Elsewhere there is no compass, only the bearing.

export const ALIGN_DEGREES = 5
export const RELEASE_DEGREES = 8
const MAX_TILT = Math.PI / 5
const MAX_ACCURACY = 10

const wrap = (degrees: number) => ((degrees % 360) + 360) % 360

/** Telegram Android's event as a magnetic heading, or null when relative or not held flat. */
export function androidHeading(event: {
  absolute: boolean
  alpha: number | null
  beta: number | null
  gamma: number | null
}): number | null {
  const { absolute, alpha, beta, gamma } = event
  if (!absolute || alpha == null || !Number.isFinite(alpha)) return null
  if (Math.abs(beta ?? 0) > MAX_TILT || Math.abs(gamma ?? 0) > MAX_TILT) return null
  return wrap((-alpha * 180) / Math.PI)
}

/** WebKit's event as a magnetic heading, or null when it isn't trustworthy. */
export function webkitHeading(heading: unknown, accuracy: unknown): number | null {
  if (typeof heading !== 'number' || !Number.isFinite(heading) || heading < 0) return null
  if (typeof accuracy !== 'number' || accuracy < 0 || accuracy > MAX_ACCURACY) return null
  return wrap(heading)
}

/**
 * Both clients report the top edge of the device, but the dial is drawn against the top of the
 * screen. [angle] is how far the screen is turned: 0, 90, 180 or 270 (or -90).
 */
export function screenHeading(heading: number, angle: number): number {
  return wrap(heading + angle)
}

/** [declination] is east-positive. */
export function trueHeading(magnetic: number, declination: number): number {
  return wrap(magnetic + declination)
}

/** Degrees to turn: positive is right. */
export function headingError(bearing: number, heading: number): number {
  return ((bearing - heading + 540) % 360) - 180
}

/** Hysteresis, as in the apps, so jitter doesn't repeat the haptic. */
export function isAligned(error: number, previously: boolean): boolean {
  return Math.abs(error) <= (previously ? RELEASE_DEGREES : ALIGN_DEGREES)
}
