import { useState } from 'preact/hooks'
import { eventsOn, monthDays } from '../core/calendar.ts'
import { civil, dayIn, hijri, monthIndex, type Day } from '../core/day.ts'
import { formatDay, monthTitle, pick } from '../core/i18n.ts'
import { deviceZone, useApp, useNow } from './state.ts'
import { Header } from './ui.tsx'

/** 0 is Sunday. 1970-01-01 was a Thursday. */
const weekday = (value: Day) => (((value + 4) % 7) + 7) % 7

// Kept while switching tabs, as the apps keep the calendar's position.
let position: number | null = null

export function Calendar() {
  const { t, locale, data, place } = useApp()
  const { months, confirmed } = data.calendar
  const today = dayIn(useNow(60_000), place?.zone ?? deviceZone())
  const current = hijri(months, today)
  const currentIndex = current ? monthIndex(current.year, current.month) : months.first
  const [index, setIndex] = useState(position ?? currentIndex)

  const last = months.first + months.starts.length - 2
  const show = (value: number) => {
    position = Math.min(last, Math.max(months.first, value))
    setIndex(position)
  }
  const year = Math.floor(index / 12)
  const month = (index % 12) + 1
  const days = monthDays(months, index)
  const firstWeekday = locale === 'ar' ? 6 : 0
  const blanks = days.length ? (weekday(days[0]!) - firstWeekday + 7) % 7 : 0
  const weekdays = new Intl.DateTimeFormat(locale, { weekday: 'narrow', timeZone: 'UTC' })
  const rows = days.map((value, offset) => ({
    value,
    date: offset + 1,
    events: eventsOn(data.calendar, { year, month, date: offset + 1 }),
  }))
  const expected = index > currentIndex && !confirmed.includes(index)

  return (
    <>
      <Header
        title={`${monthTitle(month, locale)} ${year} ${t.ah}`}
        subtitle={expected ? t.expected : undefined}
        action={
          index !== currentIndex && (
            <button class="button" onClick={() => show(currentIndex)}>{t.today}</button>
          )
        }
      />
      <div class="pager">
        <button class="button" disabled={index <= months.first} onClick={() => show(index - 1)}>
          {t.previousMonth}
        </button>
        <button class="button" disabled={index >= last} onClick={() => show(index + 1)}>
          {t.nextMonth}
        </button>
      </div>
      <div class="month">
        {Array.from({ length: 7 }, (_, offset) => (
          <span key={`w${offset}`} class="weekday" aria-hidden="true">
            {/* 1970-01-04 was a Sunday. */}
            {weekdays.format(Date.UTC(1970, 0, 4 + ((firstWeekday + offset) % 7)))}
          </span>
        ))}
        {Array.from({ length: blanks }, (_, offset) => <span key={`b${offset}`} />)}
        {rows.map(({ value, date, events }) => (
          <span
            key={value}
            class={`day${value === today ? ' is-today' : ''}${events.length ? ' has-event' : ''}`}
            aria-current={value === today ? 'date' : undefined}
            aria-label={formatDay(value, locale)}
          >
            <b>{date}</b>
            <small>{civil(value).date}</small>
          </span>
        ))}
      </div>
      <h2>{t.events}</h2>
      {rows.some(row => row.events.length) ? (
        <ul class="list">
          {rows
            .filter(row => row.events.length)
            .map(({ value, date, events }) => (
              <li key={value} class={`event${value === today ? ' is-today' : ''}`}>
                <p class="muted">
                  {date} {monthTitle(month, locale)} · {formatDay(value, locale, 'short')}
                </p>
                {events.map(event => (
                  <p key={event.id} dir="auto">
                    {pick(event.title, locale)}
                    {event.year !== undefined && event.year > 0 && (
                      <span class="muted"> · {event.year} {t.ah}</span>
                    )}
                  </p>
                ))}
              </li>
            ))}
        </ul>
      ) : (
        <p class="status">{t.noEvents}</p>
      )}
      <p class="note">{t.datesNote}</p>
    </>
  )
}
