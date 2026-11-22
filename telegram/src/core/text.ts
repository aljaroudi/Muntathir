/** At most [limit] code points, cut at a space when there is one near the end. */
export function excerpt(source: string, limit = 220): string {
  const text = source.replace(/\s+/gu, ' ').trim()
  if (text.length <= limit) return text
  const points = [...text.slice(0, limit * 2)]
  if (points.length <= limit) return text
  const cut = points.slice(0, limit).join('')
  const space = cut.lastIndexOf(' ')
  return (space > cut.length * 0.6 ? cut.slice(0, space) : cut) + '…'
}

/** Splits into parts of at most [limit] UTF-16 units, at a paragraph, line or space if possible. */
export function split(source: string, limit: number): string[] {
  const parts: string[] = []
  let rest = source.trim()
  while (rest.length > limit) {
    const head = rest.slice(0, limit)
    let cut = -1
    for (const separator of ['\n\n', '\n', ' ']) {
      const at = head.lastIndexOf(separator)
      if (at > limit / 2) {
        cut = at
        break
      }
    }
    if (cut < 0) {
      // Never split a surrogate pair.
      const last = rest.charCodeAt(limit - 1)
      cut = last >= 0xd800 && last <= 0xdbff ? limit - 1 : limit
    }
    parts.push(rest.slice(0, cut).trim())
    rest = rest.slice(cut).trim()
  }
  if (rest || !parts.length) parts.push(rest)
  return parts
}

export function httpsURL(value: string): string | undefined {
  try {
    const url = new URL(value)
    return url.protocol === 'https:' ? url.href : undefined
  } catch {
    return undefined
  }
}
