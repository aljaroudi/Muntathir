import { run } from '@grammyjs/runner'
import { isAbsolute, join, resolve } from 'node:path'
import { createHandler, type Asset } from './server/api.ts'
import { createBot } from './server/bot.ts'
import { CalendarSource } from './server/calendar.ts'
import { Content } from './server/content.ts'
import { log } from './server/log.ts'
import { Search } from './server/search.ts'
import { zoneAt } from './server/timezone.ts'

const TYPES: Record<string, string> = {
  html: 'text/html; charset=utf-8',
  js: 'text/javascript; charset=utf-8',
  css: 'text/css; charset=utf-8',
  svg: 'image/svg+xml',
  txt: 'text/plain; charset=utf-8',
  woff2: 'font/woff2',
}
const PRIVACY = {
  ar: 'https://xn--pgbou4cf.com/privacy/',
  en: 'https://xn--pgbou4cf.com/en/privacy/',
}
const HOUR = 3_600_000
const SHUTDOWN_MS = 20_000

/** Only files that exist at startup are servable, so a path can't escape the directory. */
async function loadAssets(directory: string): Promise<Map<string, Asset>> {
  const assets = new Map<string, Asset>()
  for await (const path of new Bun.Glob('**/*').scan({ cwd: directory, onlyFiles: true })) {
    const type = TYPES[path.split('.').pop()!]
    if (!type) continue
    assets.set(`/${path}`, {
      body: new Uint8Array(await Bun.file(join(directory, path)).arrayBuffer()),
      type,
      immutable: path.startsWith('assets/'),
    })
  }
  if (!assets.has('/index.html')) throw new Error('The Mini App is not built')
  return assets
}

async function main() {
  const env = Bun.env
  const token = env.TELEGRAM_BOT_TOKEN
  if (!token || !/^\d+:[\w-]{30,}$/.test(token)) {
    log('service.token_missing')
    process.exit(1)
  }
  const publicURL = env.TELEGRAM_PUBLIC_URL ?? 'https://tg.xn--pgbou4cf.com'
  const directory = (value: string | undefined, fallback: string) =>
    value && isAbsolute(value) ? value : resolve(import.meta.dir, value ?? fallback)
  // A bundle can't find geo-tz's data by itself, so fail at startup rather than on a user's message.
  if (zoneAt({ latitude: 24.7136, longitude: 46.6753 }) !== 'Asia/Riyadh')
    throw new Error('Time zone data is missing')
  const release = env.TELEGRAM_RELEASE ? (await Bun.file(env.TELEGRAM_RELEASE).text()).trim() : undefined
  const content = new Content(directory(env.TELEGRAM_DATA, '../.data'))
  const assets = await loadAssets(directory(env.TELEGRAM_APP, '../dist/app'))
  const calendar = new CalendarSource()
  const daily = Number(env.TELEGRAM_DAILY_SEARCH_LIMIT ?? 5000)
  if (!Number.isSafeInteger(daily) || daily < 1) throw new Error('Invalid TELEGRAM_DAILY_SEARCH_LIMIT')
  const search = new Search({
    url: env.TELEGRAM_SEARCH_URL ?? 'http://127.0.0.1:8788/v1/search',
    hydrate: references => content.hydrate(references),
    daily,
  })
  // Release smoke tests serve without polling, so they never compete with the live bot.
  const polling = env.TELEGRAM_POLLING !== 'false'

  const bot = createBot({ token, publicURL, privacy: PRIVACY, content, calendar, search })
  if (polling) await bot.init()

  const handler = createHandler({
    token,
    username: polling ? bot.botInfo.username : '',
    content,
    calendar,
    search,
    assets,
    release,
  })
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: Number(env.TELEGRAM_PORT ?? 8790),
    idleTimeout: 30,
    maxRequestBodySize: 16_384,
    // Bun's development error page shows source and values.
    development: false,
    fetch: handler,
  })

  if (polling) void calendar.refresh()
  const refresh = setInterval(() => void calendar.refresh(), HOUR)
  const runner = polling
    ? run(bot, {
        runner: { silent: true, fetch: { allowed_updates: ['message', 'callback_query'] } },
      })
    : null

  let stopping = false
  async function stop(status: number) {
    if (stopping) return
    stopping = true
    clearInterval(refresh)
    setTimeout(() => process.exit(1), SHUTDOWN_MS).unref()
    try {
      if (runner?.isRunning()) await runner.stop()
      await server.stop()
    } catch (error) {
      log('service.stop_failed', error)
    }
    log('service.stopped')
    process.exit(status)
  }
  process.on('SIGTERM', () => void stop(0))
  process.on('SIGINT', () => void stop(0))
  // Without this the web server would keep a dead bot's process alive after a 401 or 409.
  runner
    ?.task()
    ?.then(() => stop(stopping ? 0 : 1))
    .catch(error => {
      log('bot.polling_failed', error)
      void stop(1)
    })

  log(polling ? 'service.started' : 'service.started_without_polling')
}

main().catch(error => {
  log('service.start_failed', error)
  process.exit(1)
})
