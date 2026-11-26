/**
 * Logs say what failed, never who or what was asked. Error messages and grammY error objects can
 * carry the token (in URLs), chat IDs and message text, so only class, code and method are kept.
 */
export function log(event: string, error?: unknown) {
  const line: Record<string, unknown> = { at: new Date().toISOString(), event }
  if (error !== undefined) {
    const details = error as { name?: unknown; error_code?: unknown; method?: unknown } | null
    line.error = typeof details?.name === 'string' ? details.name : typeof error
    if (typeof details?.error_code === 'number') line.code = details.error_code
    if (typeof details?.method === 'string') line.method = details.method
  }
  console.log(JSON.stringify(line))
}
