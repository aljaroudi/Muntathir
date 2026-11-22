import { afterAll, describe, expect, spyOn, test } from 'bun:test'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import type { UserFromGetMe } from 'grammy/types'
import { createBot, MESSAGE_LIMIT, queryOf } from '../src/server/bot.ts'
import { CalendarSource } from '../src/server/calendar.ts'
import { Content } from '../src/server/content.ts'
import { publicID } from '../src/server/ids.ts'
import { Search } from '../src/server/search.ts'
import { zoneAt } from '../src/server/timezone.ts'
import { Database } from 'bun:sqlite'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { Languages } from '../src/server/languages.ts'

const directory = resolve(import.meta.dir, '../.data')
const installed = existsSync(`${directory}/rulings.db`)
const NOW = Date.UTC(2026, 10, 22, 9)

test('zones are found offline', () => {
  expect(zoneAt({ latitude: 24.7136, longitude: 46.6753 })).toBe('Asia/Riyadh')
  expect(zoneAt({ latitude: 34.0522, longitude: -118.2437 })).toBe('America/Los_Angeles')
  expect(zoneAt({ latitude: 35.6892, longitude: 51.389 })).toBe('Asia/Tehran')
  expect(zoneAt({ latitude: 0, longitude: -150 })).toStartWith('Etc/GMT')
})

test('commands are stripped from queries', () => {
  expect(queryOf('/rulings fasting')).toBe('fasting')
  expect(queryOf('/search@muntathir_bot  patience')).toBe('patience')
  expect(queryOf('patience /today')).toBe('patience /today')
})

describe.if(installed)('bot', () => {
  const quiet = spyOn(console, 'log').mockImplementation(() => {})
  afterAll(() => quiet.mockRestore())
  const content = installed ? new Content(directory) : (null as never)
  const ruling = installed
    ? new Database(`${directory}/rulings.db`, { readonly: true })
        .query<{ authority: string; language: string; id: string }, []>(
          `SELECT authority_code AS authority, language_code AS language, site_id AS id
           FROM entry ORDER BY length(body) DESC LIMIT 1`,
        )
        .get()!
    : (null as never)
  const searched: any[] = []
  const search = new Search({
    url: 'http://127.0.0.1:8788/v1/search',
    hydrate: references => content.hydrate(references),
    request: async (_, init) => {
      const body = JSON.parse(init.body as string)
      searched.push(body)
      return Response.json({
        results:
          body.kinds[0] === 'rulings'
            ? [{ kind: 'rulings', ...ruling }]
            : Array.from({ length: 8 }, (_, index) => ({ kind: 'quran', chapter: 2, verse: 280 + (index % 7) })),
      })
    },
  })

  let calls: { method: string; payload: any }[] = []
  const bot = createBot({
    token: '123456:TEST-token-not-a-real-one-0000000000000',
    publicURL: 'https://tg.example.test',
    privacy: { ar: 'https://example.test/privacy/', en: 'https://example.test/en/privacy/' },
    content,
    calendar: new CalendarSource(),
    search,
    languages: new Languages(mkdtempSync(`${tmpdir()}/bot-languages-`)),
    now: () => NOW,
    config: {
      botInfo: {
        id: 123456,
        is_bot: true,
        first_name: 'Test',
        username: 'test_bot',
      } as UserFromGetMe,
    },
  })
  bot.api.config.use(async (_, method, payload) => {
    calls.push({ method, payload })
    return { ok: true, result: true } as any
  })

  let update = 0
  const user = (language = 'en') => ({ id: 42, is_bot: false, first_name: 'T', language_code: language })
  async function message(extra: Record<string, any>, language = 'en', type = 'private') {
    calls = []
    if (extra.text?.startsWith('/'))
      extra.entities = [{ type: 'bot_command', offset: 0, length: extra.text.split(' ')[0].length }]
    await bot.handleUpdate({
      update_id: ++update,
      message: { message_id: update, date: 0, chat: { id: 42, type, first_name: 'T' }, from: user(language), ...extra },
    } as any)
    return calls
  }
  async function press(data: string, original?: string) {
    calls = []
    await bot.handleUpdate({
      update_id: ++update,
      callback_query: {
        id: '1',
        chat_instance: '1',
        from: user(),
        data,
        message: {
          message_id: 5,
          date: 1,
          chat: { id: 42, type: 'private', first_name: 'T' },
          ...(original ? { reply_to_message: { message_id: 4, date: 1, text: original } } : {}),
        },
      },
    } as any)
    return calls
  }
  const texts = () => calls.map(call => call.payload.text ?? '').join('\n')
  const buttons = () =>
    calls.flatMap(call => call.payload.reply_markup?.inline_keyboard?.flat() ?? []) as any[]
  function expectDeliverable() {
    for (const { payload } of calls) {
      expect((payload.text ?? '').length).toBeLessThanOrEqual(MESSAGE_LIMIT)
      expect(payload.parse_mode).toBeUndefined()
    }
    for (const button of buttons()) {
      if (button.callback_data) expect(Buffer.byteLength(button.callback_data)).toBeLessThanOrEqual(64)
      if (button.web_app) expect(button.web_app.url).toStartWith('https://tg.example.test/')
    }
  }

  test('start offers the app and the location button', async () => {
    await message({ text: '/start' })
    expect(buttons()[0].web_app.url).toBe('https://tg.example.test/')
    expect(calls[1]!.payload.reply_markup.keyboard[0][0].request_location).toBe(true)
    await message({ text: '/start' }, 'ar')
    expect(texts()).toContain('منتظِر')
  })

  test('a location gets times, Qibla and date, and the method switches', async () => {
    await message({ location: { latitude: 32.616012, longitude: 44.024912 } })
    expect(texts()).toContain('Jafari, Tehran')
    expect(texts()).toContain('Asia/Baghdad')
    expect(texts()).toContain('11 Jumada II 1448')
    expectDeliverable()
    const other = buttons().find(button => button.callback_data?.startsWith('p:j:'))
    expect(other.callback_data).toBe('p:j:32.616:44.025')
    await press(other.callback_data)
    expect(calls.map(call => call.method)).toEqual(['answerCallbackQuery', 'editMessageText'])
    expect(texts()).toContain('Jafari, Qum')
  })

  test('no times at high latitude says so', async () => {
    await message({ location: { latitude: 89, longitude: -179.999999 } })
    expect(texts()).toContain('Prayer times unavailable')
    expectDeliverable()
  })

  test('today and verse without a location are labeled Riyadh', async () => {
    for (const text of ['/today', '/verse']) {
      await message({ text })
      expect(texts()).toContain('Riyadh')
      expectDeliverable()
      expect(buttons().find(button => button.url).url).toStartWith('https://t.me/share/url?')
    }
  })

  test('every daily verse can be shared', async () => {
    for (let index = 0; index < 360; index += 7) {
      await message({ text: `/start ${content.dailyVerse(index)!.id}` })
      expect(buttons().find(button => button.url).url.length).toBeLessThanOrEqual(1900)
      expectDeliverable()
    }
  })

  test('plain text searches, replying to the message so buttons can read it back', async () => {
    await message({ text: 'patience\nin hardship' })
    expect(searched.at(-1)).toMatchObject({ query: 'patience in hardship', kinds: ['quran', 'hadith'] })
    expect(calls.at(-1)!.payload.reply_parameters.message_id).toBe(update)
    expectDeliverable()
    await press('s:dua', 'patience in hardship')
    expect(searched.at(-1).kinds).toEqual(['dua'])
  })

  test('rulings filter by authority and carry the notice', async () => {
    await message({ text: '/rulings fasting' })
    expect(texts()).toContain('not a source of religious rulings')
    await press('a')
    expect(buttons()).toHaveLength(content.authorities.length + 1)
    expectDeliverable()
    await press('s:rulings:sistani', '/rulings fasting')
    expect(searched.at(-1)).toMatchObject({ query: 'fasting', sources: ['sistani'] })
  })

  test('the longest ruling is cut, with authority, notice and official link', async () => {
    const id = publicID('ruling', ruling.authority, ruling.language, ruling.id)
    await press(`o:${id}`)
    const sent = calls.filter(call => call.method === 'sendMessage')
    expect(sent).toHaveLength(3)
    expect(sent[0]!.payload.text).toContain('not a source of religious rulings')
    expect(sent[2]!.payload.text).toContain('continues in the app')
    expect(buttons().some(button => button.url?.startsWith('https://'))).toBe(true)
    expectDeliverable()
  })

  test('supplications open with their translation', async () => {
    const item = content
      .supplicationList()
      .find(preview => content.supplication(preview.id)!.translations.some(value => value.language === 'en'))!
    await press(`o:${item.id}`)
    expect(texts().split('\n\n').length).toBeGreaterThan(2)
    expectDeliverable()
  })

  test('a lost query asks again', async () => {
    const before = searched.length
    await press('s:rulings')
    expect(calls[0]!.payload.text).toContain('no longer available')
    expect(searched).toHaveLength(before)
  })

  test('forged buttons only stop the spinner', async () => {
    for (const data of ['p:t:91.000:10.000', 'p:x:1.000:1.000', 'v:1:2', 's:figure', 's:dua:sistani', 's:rulings:none', 'o:../../etc', "o:q' OR 1=1 --____", 'zzz']) {
      await press(data, 'query')
      expect(`${data} ${calls.map(call => call.method)}`).toBe(`${data} answerCallbackQuery`)
    }
  })

  test('/language switches replies and can return to Telegram language', async () => {
    await message({ text: '/language' })
    expect(buttons().map(button => button.callback_data)).toEqual(['l:ar', 'l:en', 'l:auto'])
    await press('l:ar')
    expect(calls.map(call => call.method)).toEqual(['answerCallbackQuery', 'editMessageText', 'sendMessage'])
    await message({ text: '/today' })
    expect(texts()).toContain('الرياض')
    await press('l:auto')
    await message({ text: '/today' })
    expect(texts()).toContain('Riyadh')
  })

  test('groups and channels are ignored', async () => {
    for (const type of ['group', 'supergroup']) {
      await message({ text: '/today' }, 'en', type)
      expect(calls).toHaveLength(0)
    }
  })
})

describe('languages', () => {
  const { Languages } = require('../src/server/languages.ts') as typeof import('../src/server/languages.ts')
  const { mkdtempSync, readFileSync, statSync } = require('node:fs') as typeof import('node:fs')
  const { tmpdir } = require('node:os') as typeof import('node:os')

  test('choices survive a restart, are hashed, and can be forgotten', () => {
    const directory = mkdtempSync(`${tmpdir()}/languages-`)
    const first = new Languages(directory)
    first.set(987654321, 'ar')
    first.set(5, 'en')
    const raw = readFileSync(`${directory}/languages.json`, 'utf8')
    expect(raw).not.toContain('987654321')
    expect(statSync(`${directory}/languages.json`).mode & 0o777).toBe(0o600)
    const second = new Languages(directory)
    expect([second.get(987654321), second.get(5), second.get(6)]).toEqual(['ar', 'en', undefined])
    second.set(987654321, null)
    expect(new Languages(directory).get(987654321)).toBeUndefined()
  })
})
