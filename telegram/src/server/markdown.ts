import markdownIt from 'markdown-it'

// Hadith and supplications are CommonMark in the apps. Raw HTML, links, images and indented code
// are off: the text is scraped, and leading spaces in it are not code.
const parser = markdownIt('commonmark', { html: false, breaks: false, linkify: false })
  .enable('strikethrough')
  .disable(['link', 'image', 'autolink', 'reference', 'code'])

export function toHTML(source: string): string {
  return parser.render(source)
}

/** The same text without markup: paragraphs separated by blank lines, soft breaks as spaces. */
export function toPlain(source: string): string {
  const blocks: string[] = []
  const lists: (number | null)[] = []
  let marker = ''
  for (const token of parser.parse(source, {})) {
    if (token.type === 'bullet_list_open') lists.push(null)
    else if (token.type === 'ordered_list_open') lists.push(Number(token.attrGet('start') ?? 1))
    else if (token.type === 'bullet_list_close' || token.type === 'ordered_list_close') lists.pop()
    else if (token.type === 'list_item_open') {
      const number = lists.at(-1)
      marker = number == null ? '• ' : `${number}. `
      if (number != null) lists[lists.length - 1] = number + 1
    } else if (token.type === 'fence') {
      blocks.push(token.content.trim())
    } else if (token.type === 'inline') {
      let text = ''
      for (const child of token.children ?? []) {
        if (child.type === 'softbreak') text += ' '
        else if (child.type === 'hardbreak') text += '\n'
        else text += child.content
      }
      if (text.trim()) blocks.push(marker + text.trim())
      marker = ''
    }
  }
  return blocks.join('\n\n')
}
