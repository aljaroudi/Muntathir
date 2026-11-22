import type { ComponentChildren } from 'preact'
import { pick } from '../core/i18n.ts'
import type { Preview, Text } from '../core/types.ts'
import type { Failure } from './api.ts'
import { routeFor, type Route } from './routes.ts'
import { useApp } from './state.ts'
import { openLink } from './telegram.ts'

export function Header({ title, subtitle, action }: {
  title: string
  subtitle?: string
  action?: ComponentChildren
}) {
  return (
    <header class="header">
      <div>
        <h1 dir="auto">{title}</h1>
        {subtitle && <p class="muted" dir="auto">{subtitle}</p>}
      </div>
      {action}
    </header>
  )
}

export function Loading() {
  return <p class="status" role="status">{useApp().t.loading}</p>
}

export function Failed({ failure, retry }: { failure: Failure; retry?: () => void }) {
  const { t } = useApp()
  return (
    <div class="status" role="alert">
      <p>{failure === 'expired' ? t.reopen : t.failed}</p>
      {failure === 'failed' && retry && <button class="button" onClick={retry}>{t.retry}</button>}
    </div>
  )
}

/** The only innerHTML: Markdown rendered by the server with HTML, links and images off. */
export function Markup({ html, class: name = '', lang }: { html: string; class?: string; lang?: string }) {
  return <div class={`markup ${name}`} dir="auto" lang={lang} dangerouslySetInnerHTML={{ __html: html }} />
}

export function External({ url, children }: { url: string; children: ComponentChildren }) {
  return (
    <a
      class="external"
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      onClick={event => {
        event.preventDefault()
        openLink(url)
      }}
    >
      {children}
    </a>
  )
}

export function Row({ to, title, detail, trailing }: {
  to: Route
  title: string
  detail?: string
  trailing?: string | number
}) {
  const { push } = useApp()
  return (
    <li>
      <button class="row" onClick={() => push(to)}>
        <span class="row-text">
          <span class="row-title" dir="auto">{title}</span>
          {detail && <span class="row-detail" dir="auto">{detail}</span>}
        </span>
        {trailing !== undefined && <span class="muted number">{trailing}</span>}
      </button>
    </li>
  )
}

export function Previews({ items, titled = true }: { items: Preview[]; titled?: boolean }) {
  const { locale } = useApp()
  return (
    <ul class="list">
      {items.map(item => {
        const title = pick(item.title, locale)
        const body = pick(item.text, locale)
        return (
          <Row
            key={item.id}
            to={routeFor(item.id)!}
            title={titled ? title : body || title}
            detail={titled ? body : undefined}
          />
        )
      })}
    </ul>
  )
}

export function More({ show, loading, failure, load }: {
  show: boolean
  loading: boolean
  failure?: Failure
  load: () => void
}) {
  const { t } = useApp()
  if (failure) return <Failed failure={failure} retry={load} />
  if (loading) return <Loading />
  return show ? <button class="button wide" onClick={load}>{t.more}</button> : null
}

export function useText() {
  const { locale } = useApp()
  return (value: Text) => pick(value, locale)
}
