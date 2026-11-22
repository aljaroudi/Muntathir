import { useEffect, useState } from 'preact/hooks'
import { PROBLEMS } from '../core/i18n.ts'
import type { Authority, Preview, Scope, SearchProblem } from '../core/types.ts'
import { search, useGet, type Failure } from './api.ts'
import { RulingsNotice } from './library.tsx'
import { useApp } from './state.ts'
import { Failed, Header, Loading, Previews, useText } from './ui.tsx'

type Outcome = { items: Preview[] } | { problem: SearchProblem } | { failure: Failure }
type Input = { query: string; scope: Scope; authority: string; language: string }

// Kept, so Back from a result returns to the list.
let saved: { input: Input; outcome: Outcome | null } = {
  input: { query: '', scope: 'library', authority: '', language: '' },
  outcome: null,
}
let running: AbortController | null = null

export function Search() {
  const { t, locale } = useApp()
  const text = useText()
  const [input, setInput] = useState(saved.input)
  const [outcome, setOutcome] = useState(saved.outcome)
  const [busy, setBusy] = useState(false)
  const authorities = useGet<Authority[]>(input.scope === 'rulings' ? 'rulings' : null)
  const languages = authorities.data?.find(item => item.code === input.authority)?.languages

  useEffect(() => () => running?.abort(), [])

  function edit(change: Partial<Input>) {
    const next = { ...input, ...change }
    saved.input = next
    setInput(next)
    return next
  }

  async function submit(values: Input) {
    running?.abort()
    if (!values.query.trim()) {
      saved.outcome = null
      setOutcome(null)
      setBusy(false)
      return
    }
    const controller = new AbortController()
    running = controller
    setBusy(true)
    saved.outcome = null
    setOutcome(null)
    const result = await search(
      {
        query: values.query,
        scope: values.scope,
        ...(values.scope === 'rulings' && values.authority
          ? { authority: values.authority, ...(values.language ? { language: values.language } : {}) }
          : {}),
      },
      controller.signal,
    )
    if (controller.signal.aborted) return
    saved.outcome = result
    setOutcome(result)
    setBusy(false)
  }

  const scopes: [Scope, string][] = [
    ['library', t.quranHadith],
    ['dua', t.supplications],
    ['rulings', t.rulings],
  ]
  return (
    <>
      <Header title={t.search} />
      <form
        class="search"
        role="search"
        onSubmit={event => {
          event.preventDefault()
          ;(document.activeElement as HTMLElement | null)?.blur()
          void submit(input)
        }}
      >
        <input
          type="search"
          dir="auto"
          aria-label={t.search}
          placeholder={t.search}
          enterKeyHint="search"
          maxLength={1024}
          value={input.query}
          onInput={event => edit({ query: event.currentTarget.value })}
        />
        <button class="button primary" type="submit">{t.search}</button>
      </form>
      <div class="scopes">
        {scopes.map(([scope, label]) => (
          <button
            key={scope}
            class="chip"
            aria-pressed={input.scope === scope}
            onClick={() => void submit(edit({ scope }))}
          >
            {label}
          </button>
        ))}
      </div>
      {input.scope === 'rulings' && (
        <>
          <RulingsNotice />
          <div class="filters">
            <label>
              {t.authority}
              <select
                value={input.authority}
                onChange={event => void submit(edit({ authority: event.currentTarget.value, language: '' }))}
              >
                <option value="">{t.allAuthorities}</option>
                {authorities.data?.map(item => <option key={item.code} value={item.code}>{text(item.name)}</option>)}
              </select>
            </label>
            {languages && languages.length > 1 && (
              <label>
                {t.language}
                <select value={input.language} onChange={event => void submit(edit({ language: event.currentTarget.value }))}>
                  <option value="">{t.allLanguages}</option>
                  {languages.map(item => <option key={item.code} value={item.code}>{item.name}</option>)}
                </select>
              </label>
            )}
          </div>
        </>
      )}
      {busy && <Loading />}
      {outcome && 'failure' in outcome && <Failed failure={outcome.failure} retry={() => void submit(input)} />}
      {outcome && 'problem' in outcome && <p class="status" role="alert">{PROBLEMS[locale][outcome.problem]}</p>}
      {outcome && 'items' in outcome &&
        (outcome.items.length ? <Previews items={outcome.items} /> : <p class="status" role="status">{t.noResults}</p>)}
    </>
  )
}
