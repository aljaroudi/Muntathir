import { calendarMonths, type CalendarEvent } from './calendar'
import type { Locale } from './site'

export const calendarCopy = {
  en: {
    title: 'Islamic events calendar',
    description: 'Browse Islamic observances by Hijri month, with corresponding Gregorian dates.',
    home: 'Muntathir',
    year: 'Hijri year',
    browseYears: 'Browse years',
    today: 'Today',
    expected: 'Expected',
    empty: 'No events',
    ah: 'AH',
    note: 'Not all dates are verified',
    subscribe: 'Subscribe to calendar',
    controls: 'Calendar navigation',
    noScript:
      'Choose another year using the links below. Enable JavaScript for the year dropdown and current-day updates.',
  },
  ar: {
    title: 'تقويم المناسبات الإسلامية',
    description: 'تصفّح المناسبات الإسلامية حسب الشهر الهجري، مع التواريخ الميلادية المقابلة.',
    home: 'منتظِر',
    year: 'السنة الهجرية',
    browseYears: 'تصفّح السنوات',
    today: 'اليوم',
    expected: 'متوقّع',
    empty: 'لا توجد مناسبات',
    ah: 'هـ',
    note: 'ليست كل التواريخ مؤكدة',
    subscribe: 'اشترك في التقويم',
    controls: 'التنقّل في التقويم',
    noScript: 'اختر سنة أخرى من الروابط أدناه. فعّل JavaScript لاستخدام قائمة السنوات وتحديث اليوم.',
  },
}

export const calendarYears = Array.from({ length: 151 }, (_, i) => 1350 + i)
export function calendarPath(locale: Locale, year?: number) {
  return `${locale === 'ar' ? '' : '/en'}/calendar/${year === undefined ? '' : `${year}/`}`
}

function escape(text: string) {
  return text.replace(
    /[&<>"']/g,
    character =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]!
  )
}
export function monthName(start: number, locale: Locale) {
  // Midmonth stays inside the baseline month even with a seven-day correction.
  return new Intl.DateTimeFormat(`${locale}-u-ca-islamic-umalqura`, {
    month: 'long',
    timeZone: 'UTC',
  }).format(new Date((start + 14) * 86400000))
}
export function renderCalendar(
  events: CalendarEvent[],
  start: (month: number) => number,
  confirmed: number[],
  year: number,
  locale: Locale,
  now = new Date()
) {
  const copy = calendarCopy[locale],
    numbers = new Intl.NumberFormat(locale, { useGrouping: false })
  const dates = new Intl.DateTimeFormat(locale, {
    calendar: 'gregory',
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  })
  const relative = new Intl.RelativeTimeFormat(locale, { numeric: 'always' })
  return calendarMonths(events, start, confirmed, year, now)
    .map(month => {
      const name = escape(monthName(month.start, locale))
      const expected = month.expected
        ? `<span class="text-sm font-normal text-muted">${copy.expected}</span>`
        : ''
      return `<section id="month-${month.month}" class="scroll-mt-28 py-6" aria-labelledby="month-title-${month.month}"><h2 id="month-title-${month.month}" class="mb-4 flex items-center justify-between gap-4 text-xl font-medium"><a href="#month-${month.month}" class="underline-offset-4 hover:underline">${name}</a>${expected}</h2>${
        month.days.length
          ? `<ul class="divide-y divide-emerald/10 overflow-hidden rounded-2xl border border-emerald/15">${month.days
              .map(day => {
                const date = new Date(day.date * 86400000).toISOString().slice(0, 10)
                const countdown = day.today ? copy.today : relative.format(day.distance, 'day')
                return `<li id="event-${month.month}-${day.day}" ${day.next ? 'data-next-event' : ''} ${day.today ? 'aria-current="date"' : ''} class="scroll-mt-28 p-5 ${day.next ? 'bg-emerald/5' : ''}"><div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2 text-sm text-muted"><span>${numbers.format(day.day)} ${name}</span><time datetime="${date}">${month.expected ? copy.expected + ': ' : ''}${escape(dates.format(new Date(day.date * 86400000)))}</time></div>${day.next ? `<p class="mt-3 text-sm font-semibold text-moss">${month.expected && !day.today ? copy.expected + ': ' : ''}${escape(countdown)}</p>` : ''}<ul class="mt-3 space-y-3 text-base leading-loose">${day.events.map(event => `<li><h3 id="observance-${event.id}" class="scroll-mt-28 font-normal"><a href="#observance-${event.id}" class="underline-offset-4 hover:underline">${escape(event.title)}</a></h3></li>`).join('')}</ul></li>`
              })
              .join('')}</ul>`
          : `<p class="rounded-2xl border border-emerald/15 p-5 text-muted">${copy.empty}</p>`
      }</section>`
    })
    .join('')
}
