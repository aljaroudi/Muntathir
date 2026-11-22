import { describe, expect, test } from 'bun:test'
import { parseRequest } from '../../backend/api/core.ts'
import { SCOPES, type Preview } from '../src/core/types.ts'
import { normalizeQuery, Search } from '../src/server/search.ts'

const URL = 'http://127.0.0.1:8788/v1/search'
const hit: Preview = { id: 'q0000000000000000', kind: 'quran', title: { ar: '', en: '' }, text: { ar: '', en: '' } }

function setup(reply: () => Response | Promise<Response>, options = {}) {
  const sent: RequestInit[] = []
  const search = new Search({
    url: URL,
    hydrate: references => references.map(() => hit),
    request: async (_, init) => {
      sent.push(init)
      return reply()
    },
    ...options,
  })
  return { search, sent }
}
const ok = () => Response.json({ results: [{}] })

describe('search', () => {
  test("every request passes the service's own validation", async () => {
    const { search, sent } = setup(ok)
    for (const scope of SCOPES) await search.run(1, { query: 'صبر', scope })
    await search.run(1, { query: 'fasting', scope: 'rulings', authority: 'sistani', language: 'en' })
    for (const init of sent) expect(() => parseRequest(JSON.parse(init.body as string))).not.toThrow()
    expect(JSON.parse(sent[0]!.body as string).kinds).toEqual(['quran', 'hadith'])
    expect(JSON.parse(sent.at(-1)!.body as string)).toMatchObject({ sources: ['sistani'], languages: ['en'] })
  })

  test('each user gets a separate, rotating address the service accepts', () => {
    const { search } = setup(ok)
    const address = search.address(1, 0)
    expect(address).toMatch(/^100::[0-9a-f]{4}(:[0-9a-f]{4}){3}$/)
    expect(search.address(2, 0)).not.toBe(address)
    expect(search.address(1, 59_999)).toBe(address)
    expect(search.address(1, 60_000)).not.toBe(address)
    expect(setup(ok).search.address(1, 0)).not.toBe(address)
  })

  test('multiline becomes one line; empty and long are refused without a request', async () => {
    const { search, sent } = setup(ok)
    expect(normalizeQuery(' a\n\nb\t\u0007c ')).toBe('a b c')
    expect(await search.run(1, { query: ' \n ', scope: 'library' })).toEqual({ problem: 'empty' })
    expect(await search.run(1, { query: 'ص'.repeat(513), scope: 'library' })).toEqual({ problem: 'long' })
    expect(sent).toHaveLength(0)
    await search.run(1, { query: '😀'.repeat(512), scope: 'library' })
    expect(sent).toHaveLength(1)
  })

  test('failures map to a problem', async () => {
    for (const [status, problem] of [
      [400, 'invalid'],
      [413, 'invalid'],
      [429, 'limited'],
      [503, 'unavailable'],
    ] as const) {
      const { search } = setup(() => new Response('{}', { status }))
      expect(await search.run(1, { query: 'x', scope: 'library' })).toEqual({ problem })
    }
    for (const reply of [
      () => new Response('not json'),
      () => Response.json({ results: {} }),
      () => Promise.reject(new DOMException('slow', 'TimeoutError')),
    ]) {
      const { search } = setup(reply)
      expect(await search.run(1, { query: 'x', scope: 'library' })).toEqual({ problem: 'unavailable' })
    }
  })

  test('daily limits, per user and overall, reset each day', async () => {
    let now = 0
    const { search } = setup(ok, { daily: 3, dailyPerUser: 2, now: () => now })
    const run = (user: number) => search.run(user, { query: 'x', scope: 'library' })
    expect(await run(1)).toEqual({ items: [hit] })
    expect(await run(1)).toEqual({ items: [hit] })
    expect(await run(1)).toEqual({ problem: 'limited' })
    expect(await run(2)).toEqual({ items: [hit] })
    expect(await run(3)).toEqual({ problem: 'limited' })
    now = 86_400_000
    expect(await run(1)).toEqual({ items: [hit] })
  })

  test('at most four searches are in flight', async () => {
    let active = 0
    let peak = 0
    const { search } = setup(async () => {
      peak = Math.max(peak, ++active)
      await Bun.sleep(5)
      active--
      return ok()
    })
    await Promise.all(Array.from({ length: 16 }, (_, user) => search.run(user, { query: 'x', scope: 'library' })))
    expect(peak).toBe(4)
  })

  test('only a loopback service is accepted', () => {
    expect(() => new Search({ url: 'https://example.com/v1/search', hydrate: () => [] })).toThrow()
  })
})
