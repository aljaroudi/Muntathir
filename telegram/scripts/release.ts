import { createHmac } from 'node:crypto'
import { existsSync } from 'node:fs'
import { chmod, mkdir, readdir, readlink, rename, rm, symlink } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { build } from './build.ts'
import { cloneData, repository, run } from './data.ts'
import { domain, isLoaded, paths, PORT, root, SERVICE, serviceEnvironment } from './host.ts'

// Everything the bundle is built from.
const INPUTS = [
  'telegram',
  'shared/events.json',
  'shared/ummalqura.json',
  'web/src/calendar.ts',
  'web/public/calendar/corrections-v1.json',
  'apple/Muntathir/Resources/Quran',
  'apple/Muntathir/Resources/quran-daily-ids.json',
  'apple/Muntathir/Resources/quran-surahs.json',
]
const SMOKE_PORT = 8791
const SMOKE_TOKEN = '123456:release-smoke-test-not-a-real-token-0000'
/** Long enough for a 401 or 409 to end polling, and with it the process. */
const STEADY_MS = 8000

async function waitFor(check: () => Promise<boolean>, timeout: number): Promise<boolean> {
  const end = Date.now() + timeout
  while (Date.now() < end) {
    if (await check().catch(() => false)) return true
    await Bun.sleep(400)
  }
  return false
}

async function serving(port: number, id: string): Promise<boolean> {
  const response = await fetch(`http://127.0.0.1:${port}/healthz`, { signal: AbortSignal.timeout(2000) })
  return response.ok && ((await response.json()) as { release?: string }).release === id
}

function signedInitData(): string {
  const fields: Record<string, string> = {
    auth_date: String(Math.floor(Date.now() / 1000)),
    user: JSON.stringify({ id: 1 }),
  }
  const check = Object.keys(fields).sort().map(key => `${key}=${fields[key]}`).join('\n')
  const secret = createHmac('sha256', 'WebAppData').update(SMOKE_TOKEN).digest()
  return new URLSearchParams({
    ...fields,
    hash: createHmac('sha256', secret).update(check).digest('hex'),
  }).toString()
}

/** Runs the staged release on a spare port, without polling or the real token. */
async function smoke(release: string, id: string) {
  if (await serving(SMOKE_PORT, id).catch(() => false)) throw new Error('The smoke-test port is in use')
  const child = Bun.spawn([join(release, 'bun'), '--no-env-file', 'main.js'], {
    cwd: release,
    env: {
      ...serviceEnvironment(release),
      TELEGRAM_BOT_TOKEN: SMOKE_TOKEN,
      TELEGRAM_POLLING: 'false',
      TELEGRAM_PORT: String(SMOKE_PORT),
    },
    stdout: 'ignore',
    stderr: 'inherit',
  })
  try {
    if (!(await waitFor(() => serving(SMOKE_PORT, id), 30_000))) throw new Error('Smoke test: never became ready')
    const base = `http://127.0.0.1:${SMOKE_PORT}`
    const headers = { 'X-Telegram-Init-Data': signedInitData() }
    for (const path of ['/', '/licenses.txt', '/api/bootstrap', '/api/daily/0', '/api/quran/2', '/api/rulings'])
      if (!(await fetch(base + path, { headers })).ok) throw new Error(`Smoke test: ${path} failed`)
    if ((await fetch(`${base}/api/bootstrap`)).status !== 401) throw new Error('Smoke test: the API is open')
    child.kill('SIGTERM')
    if ((await child.exited) !== 0) throw new Error('Smoke test: unclean shutdown')
  } finally {
    child.kill('SIGKILL')
  }
}

async function target(link: string): Promise<string | null> {
  return readlink(link).catch(() => null)
}

async function point(link: string, to: string) {
  const temporary = `${link}.${process.pid}`
  await symlink(to, temporary)
  await rename(temporary, link)
}

async function restart(release: string): Promise<boolean> {
  const service = `${domain()}/${SERVICE}`
  // SIGTERM lets replies in progress finish, then KeepAlive starts the new release. It fails when
  // the job isn't running, and then it only needs starting.
  await run('launchctl', 'kill', 'SIGTERM', service).catch(() => run('launchctl', 'kickstart', service))
  const id = basename(release)
  if (!(await waitFor(() => serving(PORT, id), 60_000))) return false
  await Bun.sleep(STEADY_MS)
  return serving(PORT, id).catch(() => false)
}

/** Switches to [release], and back if it isn't healthy. */
async function activate(release: string) {
  const before = await target(paths.current)
  const installed = await isLoaded(SERVICE)
  await point(paths.current, release)
  if (installed && !(await restart(release))) {
    if (before && before !== release) {
      await point(paths.current, before)
      const restored = await restart(before)
      throw new Error(`Unhealthy release; rolled back (${restored ? 'healthy' : 'ALSO UNHEALTHY'})`)
    }
    throw new Error('Unhealthy release, and there is nothing to roll back to. See logs/service.log')
  }
  if (before && before !== release) await point(paths.previous, before)
  console.log(`Current release: ${basename(release)}`)
  if (!installed) console.log('The service is not installed, so nothing was restarted.')
}

async function prune() {
  const keep = [await target(paths.current), await target(paths.previous)].map(path => path && basename(path))
  for (const name of await readdir(paths.releases))
    if (!keep.includes(name) && !name.startsWith('.'))
      await rm(join(paths.releases, name), { recursive: true, force: true })
}

async function release() {
  // Uncommitted changes are built as they are; the id says so and is unique, since the commit alone doesn't name the content.
  const dirty = !!(await run('git', 'status', '--porcelain', '--', ...INPUTS))
  if (dirty) console.warn('Uncommitted changes are included in this release.')
  const { packageManager } = await Bun.file(join(repository, 'telegram/package.json')).json()
  // The copied binary is what runs live: a shim or another version would drift.
  if (packageManager !== `bun@${Bun.version}`) throw new Error(`Release with ${packageManager}`)

  await mkdir(paths.releases, { recursive: true })
  await mkdir(paths.logs, { recursive: true })
  await chmod(root, 0o700)
  const staging = join(paths.releases, `.staging-${process.pid}`)
  try {
    await build(staging)
    const digest = await cloneData(join(staging, 'data'))
    const id = `${await run('git', 'rev-parse', '--short=12', 'HEAD')}${dirty ? `-dirty${Date.now().toString(36)}` : ''}-${digest}`
    await run('cp', '-c', process.execPath, join(staging, 'bun'))
    await Bun.write(join(staging, 'RELEASE'), id)
    await smoke(staging, id)
    const destination = join(paths.releases, id)
    if (!existsSync(destination)) await rename(staging, destination)
    await activate(destination)
    await prune()
  } finally {
    await rm(staging, { recursive: true, force: true })
  }
}

async function rollback() {
  const previous = await target(paths.previous)
  if (!previous || !existsSync(previous)) throw new Error('There is no previous release')
  await activate(previous)
}

try {
  const [option, ...extra] = Bun.argv.slice(2)
  if (extra.length || (option && option !== '--rollback')) throw new Error('Usage: release.ts [--rollback]')
  await (option ? rollback() : release())
} catch (error) {
  console.error((error as Error).message)
  process.exit(1)
}
