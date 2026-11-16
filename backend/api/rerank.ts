import { JEV_URL, JEV_MODEL, jevRequest, jevRanking } from './jev.ts'
import type { Hit } from './search.ts'

export type Candidate = { id: string; text: string; hit: Hit }
export type RerankOutcome =
  'disabled' | 'skipped' | 'success' | 'busy' | 'cooldown' | 'budget' | 'failed'

/** Optional, bounded enhancement. Retrieval remains the source of references and scores. */
export class Reranker {
  private static readonly maxInFlight = 4
  readonly config: { url: string; model: string; timeout: number; provider: 'jev' } | null
  private readonly apiKey: string | undefined
  private inFlight = 0
  private retryAt = 0

  constructor(
    env: Record<string, string | undefined>,
    private readonly fetcher: typeof fetch = fetch,
    private readonly now = Date.now,
  ) {
    this.config = null
    this.apiKey = env.JEV_API_KEY || env.TYPESAFE_API_KEY
    const provider = env.SEARCH_RERANK_PROVIDER ?? 'off'
    if (!['jev', 'off'].includes(provider)) throw new Error('Invalid reranker provider')
    if (provider === 'off') return
    if (provider === 'jev') {
      if (!this.apiKey) throw new Error('JEV_API_KEY is required for Jev')
      env = {
        ...env,
        SEARCH_RERANK_URL: env.SEARCH_RERANK_URL || JEV_URL,
        SEARCH_RERANK_MODEL: env.SEARCH_RERANK_MODEL || JEV_MODEL,
      }
    }
    if (!env.SEARCH_RERANK_URL || !env.SEARCH_RERANK_MODEL) return
    const url = new URL(env.SEARCH_RERANK_URL)
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Invalid reranker URL')
    const timeout = Number(env.SEARCH_RERANK_TIMEOUT_MS ?? 2000)
    if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 2000)
      throw new Error('Reranker timeout must be 1–2000 ms')
    this.config = {
      url: url.href.replace(/\/$/, ''),
      model: env.SEARCH_RERANK_MODEL,
      timeout,
      provider: 'jev',
    }
  }

  async rank(
    query: string,
    candidates: Candidate[],
    budgetMs = Infinity,
  ): Promise<{ results: Hit[]; outcome: RerankOutcome; cacheable: boolean }> {
    const baseline = candidates.map((c) => c.hit)
    const fallback = (outcome: RerankOutcome, cacheable = false) => ({
      results: baseline,
      outcome,
      cacheable,
    })
    if (!this.config) return fallback('disabled', true)
    const selected = candidates.slice(0, 20)
    if (selected.length < 2) return fallback('skipped', true)
    if (budgetMs <= 0) return fallback('budget')
    if (this.inFlight >= Reranker.maxInFlight) return fallback('busy')
    if (this.now() < this.retryAt) return fallback('cooldown')
    this.inFlight++
    const started = this.now()
    const signal = AbortSignal.timeout(Math.min(this.config.timeout, Math.floor(budgetMs)))
    let outcome: RerankOutcome = 'failed'
    try {
      const response = await this.fetcher(this.config.url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${this.apiKey}` },
        signal,
        body: JSON.stringify(jevRequest(this.config.model, query, selected)),
      })
      if (!response.ok) throw new Error('Reranker unavailable')
      const payload = (await response.json()) as any
      const ids: unknown = jevRanking(payload, selected)
      const byID = new Map(selected.map((c) => [c.id, c.hit]))
      if (
        !Array.isArray(ids) ||
        ids.length !== selected.length ||
        new Set(ids).size !== selected.length ||
        ids.some((id) => typeof id !== 'string' || !byID.has(id))
      )
        throw new Error('Invalid ranking')
      outcome = 'success'
      return {
        results: [...ids.map((id) => byID.get(id)!), ...baseline.slice(selected.length)],
        outcome,
        cacheable: true,
      }
    } catch (error) {
      const timedOut = signal.aborted || (error instanceof Error && error.name === 'TimeoutError')
      if (!timedOut) this.retryAt = this.now() + 30_000
      return fallback('failed')
    } finally {
      this.inFlight--
      console.log(
        JSON.stringify({
          event: 'rerank',
          outcome,
          duration_ms: this.now() - started,
        }),
      )
    }
  }
}
