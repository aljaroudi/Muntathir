import { createHmac, randomBytes } from 'node:crypto'
import type { Preview, Scope, SearchProblem } from '../core/types.ts'

const KINDS: Record<Scope, string[]> = {
  library: ['quran', 'hadith'],
  quran: ['quran'],
  hadith: ['hadith'],
  dua: ['dua'],
  rulings: ['rulings'],
}
const MAX_QUERY = 512
const MAX_IN_FLIGHT = 4
const MAX_WAITING = 20
/** Retrieval plus up to 14 s of reranking. */
const TIMEOUT_MS = 18_000

export type SearchInput = {
  query: string
  scope: Scope
  authority?: string
  language?: string
  limit?: number
}
export type SearchOutcome = { items: Preview[] } | { problem: SearchProblem }

type Options = {
  /** The existing search service, on loopback. */
  url: string
  hydrate: (references: unknown[]) => Preview[]
  daily?: number
  dailyPerUser?: number
  request?: (url: string, init: RequestInit) => Promise<Response>
  now?: () => number
}

export function normalizeQuery(value: string): string {
  return value.replace(/[\s\p{Cc}]+/gu, ' ').trim()
}

/**
 * The search service limits each caller by `CF-Connecting-IP`, which only its tunnel and loopback
 * peers can set. Over loopback every Telegram user would share one bucket, so each gets a synthetic
 * address in the discard-only 100::/64 prefix. It rotates every minute, like the service's window,
 * and can't be linked to a user once the process exits.
 */
export class Search {
  private readonly secret = randomBytes(32)
  private readonly used = new Map<string, number>()
  private total = 0
  private day = -1
  private active = 0
  private readonly waiting: (() => void)[] = []

  constructor(private readonly options: Options) {
    const { hostname } = new URL(options.url)
    if (!['127.0.0.1', 'localhost', '[::1]'].includes(hostname))
      throw new Error('The search URL must be loopback')
  }

  private hmac(value: string): string {
    return createHmac('sha256', this.secret).update(value).digest('hex')
  }

  address(user: number, now: number): string {
    const hex = this.hmac(`${user}:${Math.floor(now / 60_000)}`)
    return `100::${[0, 4, 8, 12].map(at => hex.slice(at, at + 4)).join(':')}`
  }

  private allow(user: number, now: number): boolean {
    const day = Math.floor(now / 86_400_000)
    if (day !== this.day) {
      this.day = day
      this.total = 0
      this.used.clear()
    }
    const key = this.hmac(`day:${user}`)
    const count = this.used.get(key) ?? 0
    if (this.total >= (this.options.daily ?? 5000) || count >= (this.options.dailyPerUser ?? 200))
      return false
    this.total++
    this.used.set(key, count + 1)
    return true
  }

  private async acquire(): Promise<boolean> {
    if (this.active < MAX_IN_FLIGHT) {
      this.active++
      return true
    }
    if (this.waiting.length >= MAX_WAITING) return false
    // release() hands its slot straight to the next waiter.
    await new Promise<void>(resolve => this.waiting.push(resolve))
    return true
  }

  private release() {
    const next = this.waiting.shift()
    if (next) next()
    else this.active--
  }

  async run(user: number, input: SearchInput): Promise<SearchOutcome> {
    const query = normalizeQuery(input.query)
    if (!query) return { problem: 'empty' }
    if ([...query].length > MAX_QUERY) return { problem: 'long' }
    const now = (this.options.now ?? Date.now)()
    if (!this.allow(user, now)) return { problem: 'limited' }
    if (!(await this.acquire())) return { problem: 'unavailable' }
    try {
      const response = await (this.options.request ?? fetch)(this.options.url, {
        method: 'POST',
        redirect: 'error',
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: {
          'Content-Type': 'application/json',
          'CF-Connecting-IP': this.address(user, now),
        },
        body: JSON.stringify({
          query,
          kinds: KINDS[input.scope],
          languages: input.language ? [input.language] : ['ar', 'en'],
          ...(input.scope === 'rulings' && input.authority ? { sources: [input.authority] } : {}),
          limit: input.limit ?? 20,
        }),
      })
      if (response.status === 400 || response.status === 413) return { problem: 'invalid' }
      if (response.status === 429) return { problem: 'limited' }
      if (!response.ok) return { problem: 'unavailable' }
      const { results } = (await response.json()) as { results?: unknown }
      if (!Array.isArray(results)) return { problem: 'unavailable' }
      return { items: this.options.hydrate(results) }
    } catch {
      return { problem: 'unavailable' }
    } finally {
      this.release()
    }
  }
}
