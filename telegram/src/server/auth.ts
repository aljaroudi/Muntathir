import { createHmac, timingSafeEqual } from 'node:crypto'

const MAX_AGE_S = 86_400
const MAX_SKEW_S = 300
const MAX_LENGTH = 8192

/**
 * Validates Mini App `initData` and returns only the user's ID. `signature` is part of the check
 * string: only `hash` is left out.
 * https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
 */
export function authenticate(initData: string, token: string, now = Date.now()): number | null {
  if (!initData || initData.length > MAX_LENGTH) return null
  const fields = new Map<string, string>()
  for (const [key, value] of new URLSearchParams(initData)) {
    if (fields.has(key)) return null
    fields.set(key, value)
  }
  const hash = fields.get('hash') ?? ''
  if (!/^[0-9a-f]{64}$/.test(hash)) return null
  fields.delete('hash')
  const check = [...fields]
    .map(([key, value]) => `${key}=${value}`)
    .sort()
    .join('\n')
  const secret = createHmac('sha256', 'WebAppData').update(token).digest()
  const expected = createHmac('sha256', secret).update(check).digest()
  if (!timingSafeEqual(expected, Buffer.from(hash, 'hex'))) return null

  const issued = Number(fields.get('auth_date'))
  const age = now / 1000 - issued
  if (!Number.isSafeInteger(issued) || age > MAX_AGE_S || age < -MAX_SKEW_S) return null
  try {
    const { id } = JSON.parse(fields.get('user') ?? '') as { id?: unknown }
    return Number.isSafeInteger(id) && (id as number) > 0 ? (id as number) : null
  } catch {
    return null
  }
}
