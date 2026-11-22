import { createHash } from 'node:crypto'

/**
 * Public IDs: a kind letter and 16 base64url characters of a hash of the content's stable key.
 * The keys themselves reach 95 bytes and contain Arabic, over Telegram's 64-byte button limit,
 * and row IDs change whenever the databases are rebuilt.
 */
export const PREFIX = {
  verse: 'q',
  hadith: 'h',
  dua: 'd',
  ruling: 'r',
  chapter: 'c',
  topic: 't',
  introduction: 'i',
} as const
export type IDType = keyof typeof PREFIX

export function publicID(type: IDType, ...key: (string | number)[]): string {
  const hash = createHash('sha256').update(JSON.stringify(key.map(String))).digest('base64url')
  return PREFIX[type] + hash.slice(0, 16)
}

export function isPublicID(value: unknown): value is string {
  return typeof value === 'string' && /^[qhdrcti][A-Za-z0-9_-]{16}$/.test(value)
}

export class Index {
  private readonly rows = new Map<string, number>()
  private readonly ids = new Map<number, string>()

  constructor(private readonly type: IDType) {}

  add(row: number, ...key: (string | number)[]) {
    const id = publicID(this.type, ...key)
    if (this.rows.has(id)) throw new Error(`Duplicate ${this.type} key`)
    this.rows.set(id, row)
    this.ids.set(row, id)
  }

  row(id: string): number | undefined {
    return this.rows.get(id)
  }

  id(row: number): string {
    const id = this.ids.get(row)
    if (id === undefined) throw new Error(`Unknown ${this.type} row`)
    return id
  }

  resolve(...key: (string | number)[]): number | undefined {
    return this.rows.get(publicID(this.type, ...key))
  }

  get size() {
    return this.rows.size
  }
}
