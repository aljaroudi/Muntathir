import { hash, MODEL, parseRequest, PROFILE, reference, validVector } from './core.ts'
import { Qdrant, retrieve } from './search.ts'
import { Store } from './store.ts'

function isIP(ip: string) {
  return (
    (/^(\d{1,3}\.){3}\d{1,3}$/.test(ip) && ip.split('.').every((part) => Number(part) <= 255)) ||
    (ip.includes(':') && /^[0-9a-f:.%]+$/i.test(ip))
  )
}

export function createHandler(
  store: Store,
  db: Qdrant,
  env: Record<string, string | undefined> = Bun.env,
) {
  const inflight = new Map<string, Promise<number[]>>()
  function number(key: string, fallback: number) {
    const n = Number(env[key] ?? fallback)
    if (!Number.isSafeInteger(n) || n < 1) throw new Error(`Invalid ${key}`)
    return n
  }
  const ipLimit = number('SEARCH_IP_PER_MINUTE', 30),
    dailyLimit = number('SEARCH_DAILY_EMBEDDING_LIMIT', 150000)
  if (!env.SEARCH_RATE_SALT || !env.GEMINI_API_KEY) throw new Error('Missing server credentials')
  const disabled = env.SEARCH_DISABLE_CACHE === 'true'
  return async (request: Request, peer = ''): Promise<Response> => {
    const started = performance.now()
    let stage = 'request'
    const reply = (status: number, body: unknown, timing?: string) => {
      const data = JSON.stringify(body)
      if (new URL(request.url).pathname === '/v1/search') {
        console.log(
          JSON.stringify({
            event: 'response',
            status,
            response_bytes: Buffer.byteLength(data),
            total_ms: performance.now() - started,
          }),
        )
      }
      return new Response(data, {
        status,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
          ...(timing ? { 'Server-Timing': timing } : {}),
          ...(status === 429 ? { 'Retry-After': '60' } : {}),
        },
      })
    }
    const path = new URL(request.url).pathname
    if (path === '/healthz' && request.method === 'GET') {
      try {
        await db.active()
        return reply(200, { status: 'ready' })
      } catch {
        return reply(503, { status: 'unavailable' })
      }
    }
    if (path !== '/v1/search') return reply(404, { error: 'not_found' })
    if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' })
    let input, direct
    try {
      const reader = request.body?.getReader()
      if (!reader) return reply(400, { error: 'invalid_request' })
      const chunks: Uint8Array[] = []
      let size = 0
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        size += value.length
        if (size > 8192) {
          await reader.cancel()
          return reply(413, { error: 'request_too_large' })
        }
        chunks.push(value)
      }
      const body = new Uint8Array(size)
      let offset = 0
      for (const c of chunks) {
        body.set(c, offset)
        offset += c.length
      }
      input = parseRequest(JSON.parse(new TextDecoder().decode(body)))
      direct = reference(input.query)
    } catch {
      return reply(400, { error: 'invalid_request' })
    }
    try {
      // Only the loopback tunnel may supply CF-Connecting-IP. Never expose this listener to LAN.
      if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(peer))
        return reply(403, { error: 'forbidden' })
      const ip = env.SEARCH_TRUST_TUNNEL === 'true' ? request.headers.get('cf-connecting-ip') : peer
      if (!ip || !isIP(ip)) return reply(503, { error: 'search_unavailable' })
      stage = 'quota'
      if (
        !store.take(`ip:${await hash(`${env.SEARCH_RATE_SALT}:${ip}`)}`, ipLimit, 60) ||
        !store.take('global', 1800, 60)
      )
        return reply(429, { error: 'rate_limited' })
      stage = 'revision'
      const collection = await db.active()
      const key = `result:${await hash(JSON.stringify({ input, collection, profile: PROFILE, pipeline: 'qdrant-bm25-all-terms-rrf60-v1' }))}`
      const cached = disabled ? undefined : store.get(key)
      if (cached) {
        console.log(
          JSON.stringify({
            event: 'search',
            cache: 'result',
            total_ms: performance.now() - started,
          }),
        )
        return reply(200, cached)
      }
      let vector: number[] | null = null,
        providerMs = 0,
        tokens = 0,
        embeddingHit = false
      if (!direct) {
        const embeddingKey = `embedding:${await hash(`${PROFILE}:${input.query}`)}`
        const previous = disabled ? undefined : store.get(embeddingKey)
        if (validVector(previous)) {
          vector = previous
          embeddingHit = true
        } else {
          stage = 'provider'
          let pending = inflight.get(embeddingKey)
          if (!pending) {
            if (!store.take('embedding:day', dailyLimit, 86400))
              return reply(429, { error: 'daily_limit' })
            const query = input.query
            pending = (async () => {
              const start = performance.now()
              const response = await fetch(
                `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:embedContent`,
                {
                  method: 'POST',
                  headers: {
                    'x-goog-api-key': env.GEMINI_API_KEY!,
                    'Content-Type': 'application/json',
                  },
                  body: JSON.stringify({
                    content: {
                      parts: [{ text: `task: search result | query: ${query}` }],
                    },
                    outputDimensionality: 1536,
                  }),
                  signal: AbortSignal.timeout(8000),
                },
              )
              if (!response.ok) throw new Error('Embedding unavailable')
              const payload = (await response.json()) as any
              if (!validVector(payload.embedding?.values)) throw new Error('Invalid embedding')
              providerMs = performance.now() - start
              tokens = payload.tokenCount ?? payload.usageMetadata?.promptTokenCount ?? 0
              if (!disabled) store.put(embeddingKey, payload.embedding.values, 3600)
              return payload.embedding.values as number[]
            })()
            inflight.set(embeddingKey, pending)
            void pending.finally(() => inflight.delete(embeddingKey)).catch(() => {})
          }
          vector = await pending
        }
      }
      stage = 'retrieval'
      const start = performance.now()
      const { results } = await retrieve(db, collection, input, vector, direct)
      const retrievalMs = performance.now() - start
      const payload = { results }
      if (!disabled) store.put(key, payload, 300)
      console.log(
        JSON.stringify({
          event: 'search',
          cache: embeddingHit ? 'embedding' : 'miss',
          direct: !!direct,
          embedding_tokens: tokens,
          provider_ms: providerMs,
          retrieval_ms: retrievalMs,
          total_ms: performance.now() - started,
        }),
      )
      return reply(
        200,
        payload,
        `retrieval;dur=${retrievalMs.toFixed(2)}, provider;dur=${providerMs.toFixed(2)}`,
      )
    } catch {
      console.error(
        JSON.stringify({
          event: 'search_error',
          stage,
          total_ms: performance.now() - started,
        }),
      )
      return reply(503, { error: 'search_unavailable' })
    }
  }
}
if (import.meta.main) {
  const store = new Store(Bun.env.SEARCH_STATE_PATH ?? 'backend/work/search.sqlite')
  const handle = createHandler(
    store,
    new Qdrant(Bun.env.QDRANT_URL ?? 'http://127.0.0.1:56333', Bun.env.QDRANT_API_KEY),
  )
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: Number(Bun.env.SEARCH_PORT ?? 8788),
    maxRequestBodySize: 8192,
    idleTimeout: 15,
    fetch(request, server) {
      return handle(request, server.requestIP(request)?.address)
    },
  })
  const cleanup = setInterval(() => store.prune(), 600000)
  cleanup.unref()
  for (const signal of ['SIGINT', 'SIGTERM'] as const)
    process.on(signal, async () => {
      clearInterval(cleanup)
      await server.stop(false)
      store.db.close()
    })
  console.log(`Search listening on ${server.url}`)
}
