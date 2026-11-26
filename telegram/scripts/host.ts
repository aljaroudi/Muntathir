import { homedir } from 'node:os'
import { join } from 'node:path'

export const HOST = 'tg.xn--pgbou4cf.com'
export const PUBLIC_URL = `https://${HOST}`
export const PORT = 8790
export const SERVICE = 'com.muntathir.telegram'

// The override exists to test releases without touching the live directory.
export const root =
  Bun.env.MUNTATHIR_TELEGRAM_HOME ?? join(homedir(), 'Library/Application Support/Muntathir/telegram')
export const paths = {
  env: join(root, '.env'),
  current: join(root, 'current'),
  previous: join(root, 'previous'),
  releases: join(root, 'releases'),
  logs: join(root, 'logs'),
}

/** What the service needs from [release]. The token comes only from `.env`. */
export function serviceEnvironment(release: string): Record<string, string> {
  return {
    TELEGRAM_DATA: join(release, 'data'),
    TELEGRAM_APP: join(release, 'app'),
    TELEGRAM_RELEASE: join(release, 'RELEASE'),
    TELEGRAM_PUBLIC_URL: PUBLIC_URL,
    // Must be set before the bundle loads geo-tz.
    GEO_TZ_DATA_PATH: join(release, 'tz'),
  }
}

export const domain = () => `gui/${process.getuid!()}`

export async function isLoaded(label: string): Promise<boolean> {
  const child = Bun.spawn(['launchctl', 'print', `${domain()}/${label}`], { stdout: 'ignore', stderr: 'ignore' })
  return (await child.exited) === 0
}
