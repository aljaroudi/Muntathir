import { afterAll, describe, expect, spyOn, test } from 'bun:test'
import { createHmac } from 'node:crypto'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { AUTH_HEADER, createHandler } from '../src/server/api.ts'
import { authenticate } from '../src/server/auth.ts'
import { CalendarSource } from '../src/server/calendar.ts'
import { Content } from '../src/server/content.ts'
import { log } from '../src/server/log.ts'
import { Search } from '../src/server/search.ts'

const TOKEN = '123456:TEST-token-not-a-real-one-0000000000000'
const NOW = Date.UTC(2026, 10, 22, 12)

function sign(fields: Record<string, string>, token = TOKEN): string {
  const check = Object.keys(fields).sort().map(key => `${key}=${fields[key]}`).join('\n')
  const secret = createHmac('sha256', 'WebAppData').update(token).digest()
  const hash = createHmac('sha256', secret).update(check).digest('hex')
  return new URLSearchParams({ ...fields, hash }).toString()
}
const valid = {
  auth_date: String(NOW / 1000 - 60),
  query_id: 'AAE',
  signature: 'ed25519-signature',
  user: JSON.stringify({ id: 42, first_name: 'ليلى & Co', language_code: 'ar' }),
}

describe('initData', () => {
  test('accepts a valid signature', () => {
    expect(authenticate(sign(valid), TOKEN, NOW)).toBe(42)
  })
  test('rejects missing, tampered, duplicated, foreign and malformed data', () => {
    const data = sign(valid)
    for (const bad of [
      '',
      'hash=00',
      data.replace('%22id%22%3A42', '%22id%22%3A43'),
      `${data}&extra=1`,
      `${data}&auth_date=1`,
      data.replace(/signature=[^&]+&?/, ''),
      sign(valid, '999:another-bot'),
      sign({ ...valid, user: 'not json' }),
      sign({ auth_date: valid.auth_date }),
      'x'.repeat(9000),
    ])
      expect(authenticate(bad, TOKEN, NOW)).toBeNull()
  })
  test('expires after a day', () => {
    for (const offset of [-86_401, 301])
      expect(authenticate(sign({ ...valid, auth_date: String(NOW / 1000 + offset) }), TOKEN, NOW)).toBeNull()
    expect(authenticate(sign({ ...valid, auth_date: String(NOW / 1000 - 86_400) }), TOKEN, NOW)).toBe(42)
  })
})

test('logs carry no token, text, ID or coordinates', () => {
  const lines: string[] = []
  const spy = spyOn(console, 'log').mockImplementation(line => void lines.push(String(line)))
  log('bot.failed', {
    name: 'GrammyError',
    error_code: 400,
    method: 'sendMessage',
    message: `https://api.telegram.org/bot${TOKEN}/sendMessage CANARY`,
    payload: { chat_id: 987654321, text: 'CANARY 32.616,44.024' },
  })
  spy.mockRestore()
  expect(lines[0]).toContain('sendMessage')
  for (const secret of [TOKEN, 'CANARY', '987654321', '32.616']) expect(lines[0]).not.toContain(secret)
})

const directory = resolve(import.meta.dir, '../.data')
const installed = existsSync(`${directory}/rulings.db`)

describe.if(installed)('api', () => {
  const quiet = spyOn(console, 'log').mockImplementation(() => {})
  afterAll(() => quiet.mockRestore())
  const content = installed ? new Content(directory) : (null as never)
  const sent: RequestInit[] = []
  let status = 200
  const search = new Search({
    url: 'http://127.0.0.1:8788/v1/search',
    hydrate: references => content.hydrate(references),
    request: async (_, init) => {
      sent.push(init)
      return Response.json({ results: [{ kind: 'quran', chapter: 2, verse: 255, score: 1 }] }, { status })
    },
  })
  const handle = createHandler({
    token: TOKEN,
    username: () => 'test_bot',
    content,
    calendar: new CalendarSource(),
    search,
    now: () => NOW,
    assets: new Map([['/index.html', { body: new Uint8Array([104, 105]), type: 'text/html', immutable: false }]]),
  })
  const call = (path: string, init: RequestInit = {}, auth: string | null = sign(valid)) =>
    handle(
      new Request(`http://localhost${path}`, {
        ...init,
        headers: { ...(init.headers as Record<string, string>), ...(auth ? { [AUTH_HEADER]: auth } : {}) },
      }),
    )
  const post = (body: unknown, headers = {}) =>
    call('/api/search', { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), headers })

  test('every data route needs initData', async () => {
    for (const path of ['/api/bootstrap', '/api/quran', '/api/hadith', '/api/rulings', '/api/search', '/api/unknown']) {
      expect((await call(path, {}, null)).status).toBe(401)
      expect((await call(path, {}, 'auth_date=1&hash=' + '0'.repeat(64))).status).toBe(401)
    }
  })

  test('reads', async () => {
    const authority = content.authorities[0]!
    const language = authority.languages[0]!.code
    const collection = content.collections[0]!.id
    for (const path of [
      '/api/bootstrap',
      '/api/daily/0',
      '/api/quran',
      '/api/quran/2?after=50',
      `/api/verse/${content.surah(1)!.items[0]!.id}`,
      '/api/hadith',
      `/api/hadith/${collection}`,
      `/api/chapter/${content.contents(collection)!.books[0]!.chapters[0]!.id}`,
      '/api/supplications',
      `/api/supplication/${content.supplicationList()[0]!.id}`,
      '/api/rulings',
      `/api/rulings/${authority.code}/${language}`,
      `/api/topic/${content.rulingContents(authority.code, language)![0]!.id}`,
    ])
      expect(`${path} ${(await call(path)).status}`).toBe(`${path} 200`)
  })

  test('forged paths find nothing', async () => {
    for (const path of [
      '/api/quran/0',
      '/api/quran/115',
      '/api/quran/2?after=1;DROP',
      '/api/daily/360',
      '/api/verse/q0000000000000000',
      '/api/narration/%27%20OR%201=1',
      '/api/rulings/none/ar',
      '/api/quran/1/2/3',
      '/api/bootstrap/x',
    ])
      expect(`${path} ${(await call(path)).status}`).toBe(`${path} 404`)
  })

  test('search validates input and hydrates hits', async () => {
    const good = await post({ query: 'الكرسي\nآية' })
    expect(good.status).toBe(200)
    expect(((await good.json()) as any).items[0].title.en).toEndWith('2:255')
    for (const body of ['nope', 'null', '[]', { query: 1 }, { query: 'x', scope: 'figure' }, { query: 'x', authority: 'sistani' }, { query: 'x', language: 'zz' }])
      expect((await post(body)).status).toBe(400)
    expect((await post({ query: 'x'.repeat(5000) })).status).toBe(413)
  })

  test("a client's IP headers are never forwarded", async () => {
    sent.length = 0
    await post({ query: 'x' }, { 'cf-connecting-ip': '203.0.113.9', 'x-forwarded-for': '203.0.113.9' })
    expect(JSON.stringify(sent[0]!.headers)).not.toContain('203.0.113.9')
    expect(JSON.stringify(sent[0]!.headers)).toContain('100::')
  })

  test('service failures keep their meaning', async () => {
    for (const [from, to] of [[429, 429], [503, 503]] as const) {
      status = from
      expect((await post({ query: 'x' })).status).toBe(to)
    }
    status = 200
  })

  test('static files are exact, with a CSP that allows only Telegram framing', async () => {
    const page = await call('/', {}, null)
    expect(await page.text()).toBe('hi')
    const csp = page.headers.get('content-security-policy')!
    expect(csp).toContain('frame-ancestors https://web.telegram.org')
    expect(csp).not.toContain('unsafe')
    expect(page.headers.get('x-frame-options')).toBeNull()
    for (const path of ['/.env', '/%2e%2e/%2e%2e/.env', '/main.js', '/rulings.db'])
      expect((await call(path, {}, null)).status).toBe(404)
  })
})
