import { SCOPES, type Scope } from '../core/types.ts'
import { authenticate } from './auth.ts'
import type { CalendarSource } from './calendar.ts'
import type { Content } from './content.ts'
import { isPublicID } from './ids.ts'
import { log } from './log.ts'
import type { Search } from './search.ts'

const SECURITY_HEADERS = {
  'Content-Security-Policy': [
    "default-src 'none'",
    "script-src 'self' https://telegram.org",
    "style-src 'self'",
    "img-src 'self' data:",
    "font-src 'self'",
    "connect-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
    // Telegram Web shows Mini Apps in an iframe, so no X-Frame-Options.
    'frame-ancestors https://web.telegram.org https://*.web.telegram.org',
  ].join('; '),
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex',
}

const MAX_BODY = 4096
export const AUTH_HEADER = 'x-telegram-init-data'

export type Asset = { body: Uint8Array<ArrayBuffer>; type: string; immutable: boolean }

type Dependencies = {
  token: string
  username: string
  content: Content
  calendar: CalendarSource
  search: Search
  assets: Map<string, Asset>
  now?: () => number
}

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...SECURITY_HEADERS,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}

function cursor(url: URL): number | undefined | null {
  const value = url.searchParams.get('after')
  if (value === null) return undefined
  return /^-?\d{1,15}$/.test(value) ? Number(value) : null
}

export function createHandler({
  token,
  username,
  content,
  calendar,
  search,
  assets,
  now = Date.now,
}: Dependencies) {
  function read(url: URL): unknown {
    const [resource, first = '', second = '', ...rest] = url.pathname.slice('/api/'.length).split('/')
    const after = cursor(url)
    if (rest.length || after === null) return null
    const id = isPublicID(first) && !second ? first : null
    switch (resource) {
      case 'bootstrap':
        return first ? null : { calendar: calendar.current(now()), username }
      case 'daily':
        return /^\d{1,3}$/.test(first) && !second ? content.dailyVerse(Number(first)) : null
      case 'verse':
        return id && content.verse(id)
      case 'quran':
        if (!first) return content.surahs
        return /^\d{1,3}$/.test(first) && !second ? content.surah(Number(first), after) : null
      case 'hadith':
        return first ? content.contents(first) : content.collections
      case 'chapter':
        return id && content.chapter(id, after)
      case 'narration':
        return id && content.narration(id)
      case 'supplications':
        return first ? null : content.supplicationList()
      case 'supplication':
        return id && content.supplication(id)
      case 'rulings':
        if (!first) return content.authorities
        return second ? content.rulingContents(first, second) : null
      case 'topic':
        return id && content.topic(id, after)
      case 'ruling':
        return id && content.ruling(id)
      default:
        return null
    }
  }

  async function runSearch(request: Request, user: number): Promise<Response> {
    const raw = await request.text()
    if (Buffer.byteLength(raw) > MAX_BODY) return reply(413, { problem: 'long' })
    let input: Record<string, unknown>
    try {
      input = JSON.parse(raw)
      if (typeof input !== 'object' || input === null) return reply(400, { problem: 'invalid' })
    } catch {
      return reply(400, { problem: 'invalid' })
    }
    const { query, scope = 'library', authority, language } = input
    const selected = content.authorities.find(item => item.code === authority)
    const languages = selected?.languages.map(item => item.code) ?? ['ar', 'en']
    if (
      typeof query !== 'string' ||
      !SCOPES.includes(scope as Scope) ||
      (authority !== undefined && (!selected || scope !== 'rulings')) ||
      (language !== undefined && !languages.includes(language as string))
    )
      return reply(400, { problem: 'invalid' })
    const outcome = await search.run(user, {
      query,
      scope: scope as Scope,
      authority: selected?.code,
      language: language as string | undefined,
    })
    if (!('problem' in outcome)) return reply(200, outcome)
    const status = outcome.problem === 'limited' ? 429 : outcome.problem === 'unavailable' ? 503 : 400
    return reply(status, outcome)
  }

  return async (request: Request): Promise<Response> => {
    try {
      const url = new URL(request.url)
      if (url.pathname === '/healthz' && request.method === 'GET') return reply(200, { status: 'ready' })

      if (!url.pathname.startsWith('/api/')) {
        const asset = assets.get(url.pathname === '/' ? '/index.html' : url.pathname)
        if (!asset) return reply(404, { error: 'not_found' })
        if (request.method !== 'GET' && request.method !== 'HEAD')
          return reply(405, { error: 'method_not_allowed' })
        return new Response(request.method === 'HEAD' ? null : asset.body, {
          headers: {
            ...SECURITY_HEADERS,
            'Content-Type': asset.type,
            'Cache-Control': asset.immutable ? 'public, max-age=31536000, immutable' : 'no-store',
          },
        })
      }

      const user = authenticate(request.headers.get(AUTH_HEADER) ?? '', token, now())
      if (user === null) return reply(401, { error: 'unauthorized' })
      if (url.pathname === '/api/search') {
        return request.method === 'POST'
          ? await runSearch(request, user)
          : reply(405, { error: 'method_not_allowed' })
      }
      if (request.method !== 'GET') return reply(405, { error: 'method_not_allowed' })
      const found = read(url)
      return found ? reply(200, found) : reply(404, { error: 'not_found' })
    } catch (error) {
      log('api.failed', error)
      return reply(500, { error: 'failed' })
    }
  }
}
