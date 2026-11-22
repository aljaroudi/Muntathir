import { useCallback, useEffect, useState } from 'preact/hooks'
import type { Page, Preview, Scope, SearchProblem } from '../core/types.ts'
import { initData } from './telegram.ts'

export type Failure = 'failed' | 'expired'
export type State<T> = { data?: T; failure?: Failure }

const headers = { 'X-Telegram-Init-Data': initData }
const cache = new Map<string, unknown>()

class Expired extends Error {}

export async function get<T>(path: string): Promise<T> {
  if (cache.has(path)) return cache.get(path) as T
  const response = await fetch(`/api/${path}`, { headers })
  if (response.status === 401) throw new Expired()
  if (!response.ok) throw new Error('Request failed')
  const data = (await response.json()) as T
  cache.set(path, data)
  return data
}

export const failureOf = (error: unknown): Failure => (error instanceof Expired ? 'expired' : 'failed')

/** A cached GET. Null waits. */
export function useGet<T>(path: string | null): State<T> & { retry: () => void } {
  const cached = () => (path && cache.has(path) ? { data: cache.get(path) as T } : {})
  const [state, setState] = useState<State<T> & { path?: string | null }>(() => ({ ...cached(), path }))
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    setState({ ...cached(), path })
    if (!path || cache.has(path)) return
    let live = true
    get<T>(path).then(
      data => live && setState({ data, path }),
      error => live && setState({ failure: failureOf(error), path }),
    )
    return () => {
      live = false
    }
  }, [path, attempt])
  // Never show the previous path's data for a frame.
  const current = state.path === path ? state : cached()
  return { ...current, retry: useCallback(() => setAttempt(value => value + 1), []) }
}

// Kept outside components, so Back returns to the same loaded pages.
const loaded = new Map<string, { head: unknown; items: unknown[]; next?: number }>()

export function usePages<P extends Page<unknown>>(path: string) {
  type Item = P['items'][number]
  const [, render] = useState(0)
  const [loading, setLoading] = useState(false)
  const [failure, setFailure] = useState<Failure>()
  const current = loaded.get(path)

  const more = useCallback(async () => {
    const before = loaded.get(path)
    if (before && before.next === undefined) return
    setLoading(true)
    setFailure(undefined)
    try {
      const page = await get<P>(before ? `${path}?after=${before.next}` : path)
      // A second call for the same cursor changes nothing.
      if (loaded.get(path) === before)
        loaded.set(path, {
          head: before?.head ?? page,
          items: [...(before?.items ?? []), ...page.items],
          next: page.next,
        })
      render(value => value + 1)
    } catch (error) {
      setFailure(failureOf(error))
    } finally {
      setLoading(false)
    }
  }, [path])

  useEffect(() => {
    if (!loaded.has(path)) void more()
  }, [path, more])

  return {
    head: current?.head as P | undefined,
    items: (current?.items ?? []) as Item[],
    hasMore: current?.next !== undefined,
    loading,
    failure,
    more,
  }
}

export async function search(
  input: { query: string; scope: Scope; authority?: string; language?: string },
  signal: AbortSignal,
): Promise<{ items: Preview[] } | { problem: SearchProblem } | { failure: Failure }> {
  try {
    const response = await fetch('/api/search', {
      method: 'POST',
      signal,
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
    })
    if (response.status === 401) return { failure: 'expired' }
    return await response.json()
  } catch {
    return { failure: 'failed' }
  }
}
