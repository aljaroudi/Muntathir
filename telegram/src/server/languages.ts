import { createHmac, randomBytes } from 'node:crypto'
import { chmodSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { Locale } from '../core/i18n.ts'

type State = { secret: string; choices: Record<string, Locale> }

/**
 * The bot's only stored user data: a chosen chat language, keyed by a keyed hash of the account ID.
 * Bots can't use Telegram's per-user storage (only Mini Apps can), so it lives here. Choosing
 * "Telegram's language" deletes the entry.
 */
export class Languages {
  private readonly file: string
  private state: State

  constructor(directory: string) {
    mkdirSync(directory, { recursive: true, mode: 0o700 })
    this.file = join(directory, 'languages.json')
    try {
      const saved = JSON.parse(readFileSync(this.file, 'utf8')) as State
      if (typeof saved.secret !== 'string' || typeof saved.choices !== 'object') throw new Error('Invalid')
      this.state = saved
    } catch (error) {
      if ((error as { code?: string }).code !== 'ENOENT') throw error
      this.state = { secret: randomBytes(32).toString('hex'), choices: {} }
    }
  }

  private key(user: number): string {
    return createHmac('sha256', this.state.secret).update(String(user)).digest('base64url')
  }

  get(user: number): Locale | undefined {
    const choice = this.state.choices[this.key(user)]
    return choice === 'ar' || choice === 'en' ? choice : undefined
  }

  /** Null forgets the choice. */
  set(user: number, locale: Locale | null) {
    const key = this.key(user)
    if (locale) this.state.choices[key] = locale
    else delete this.state.choices[key]
    // Written whole and renamed, so a crash never leaves half a file.
    const temporary = `${this.file}.${process.pid}`
    writeFileSync(temporary, JSON.stringify(this.state), { mode: 0o600 })
    chmodSync(temporary, 0o600)
    renameSync(temporary, this.file)
  }
}
