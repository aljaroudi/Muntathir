import { Database } from 'bun:sqlite'

export class Store {
  db: Database
  constructor(path: string) {
    this.db = new Database(path, { create: true, strict: true })
    this.db.run(`PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, value TEXT NOT NULL, expires INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS quota(key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);`)
  }
  get(key: string, now = Date.now()): unknown {
    const row = this.db
      .query('SELECT value FROM cache WHERE key=? AND expires>?')
      .get(key, now) as { value: string } | null
    return row ? JSON.parse(row.value) : undefined
  }
  put(key: string, value: unknown, seconds: number) {
    this.db
      .query('INSERT OR REPLACE INTO cache VALUES(?,?,?)')
      .run(key, JSON.stringify(value), Date.now() + seconds * 1000)
  }
  take(key: string, limit: number, seconds: number, now = Date.now()): boolean {
    const expires = (Math.floor(now / (seconds * 1000)) + 1) * seconds * 1000
    return this.db
      .transaction(() => {
        const row = this.db.query('SELECT count,expires FROM quota WHERE key=?').get(key) as {
          count: number
          expires: number
        } | null
        const count = row && row.expires > now ? row.count : 0
        if (count >= limit) return false
        this.db.query('INSERT OR REPLACE INTO quota VALUES(?,?,?)').run(key, count + 1, expires)
        return true
      })
      .immediate()
  }
  prune() {
    this.db.query('DELETE FROM cache WHERE expires<=?').run(Date.now())
    this.db.query('DELETE FROM quota WHERE expires<=?').run(Date.now())
  }
}
