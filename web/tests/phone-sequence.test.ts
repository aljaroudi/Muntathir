import { expect, test } from 'bun:test'
import { nextMediaIndex } from '@/phone-sequence'

test('the tour reaches the video and wraps in both directions', () => {
  const count = 11
  let current = 0
  const seen = [current]
  for (let i = 0; i < count; i++) {
    current = nextMediaIndex(current, count, new Set())
    seen.push(current)
  }
  expect(seen).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0])
  expect(nextMediaIndex(0, count, new Set(), -1)).toBe(10)
})

test('failed screenshots or video cannot trap the tour', () => {
  expect(nextMediaIndex(9, 11, new Set([10, 0]))).toBe(1)
  expect(nextMediaIndex(0, 11, new Set([10, 9]), -1)).toBe(8)
  expect(nextMediaIndex(1, 3, new Set([0, 2]))).toBe(1)
  expect(nextMediaIndex(0, 3, new Set([0, 1, 2]))).toBe(-1)
})

test('mounted tour defers video and pauses for controls, visibility, and reduced motion', async () => {
  const { jest } = await import('bun:test')
  const { mountPhoneSequence } = await import('@/phone-sequence')
  class Element extends EventTarget {
    dataset: Record<string, string> = {}
    textContent = ''
    hidden = false
    disabled = false
    setAttribute() {}
    click() {
      this.dispatchEvent(new Event('click'))
    }
  }
  class Image extends Element {
    complete = true
    naturalWidth = 572
  }
  const today = new Image(),
    quran = new Image()
  today.dataset.caption = 'Today'
  quran.dataset.caption = 'Quran'
  const video = Object.assign(new Element(), {
    src: '',
    currentTime: 0,
    paused: true,
    hasAttribute() {
      return this.src !== ''
    },
    pause() {
      this.paused = true
    },
    async play() {
      this.paused = false
    },
  })
  video.dataset = { caption: 'Sky', src: '/sky.webm' }
  const caption = new Element(),
    toggle = new Element(),
    previous = new Element(),
    next = new Element()
  caption.textContent = 'Today'
  toggle.dataset = { play: 'Play', pause: 'Pause' }
  const controls = Object.assign(new Element(), {
    querySelectorAll: () => [previous, toggle, next],
  })
  const elements: Record<string, Element> = {
    video,
    '[data-preview-caption]': caption,
    '[data-preview-controls]': controls,
    '[data-preview-toggle]': toggle,
    '[data-preview-step="-1"]': previous,
    '[data-preview-step="1"]': next,
  }
  const preview = {
    dataset: { unavailable: 'Unavailable' },
    querySelectorAll: () => [today, quran, video],
    querySelector: (selector: string) => elements[selector],
  }
  const document = Object.assign(new EventTarget(), { hidden: false })
  const motion = Object.assign(new EventTarget(), { matches: false })
  let visibility: (entries: { isIntersecting: boolean }[]) => void = () => {}
  const replacements = {
    document,
    matchMedia: () => motion,
    HTMLImageElement: Image,
    IntersectionObserver: class {
      constructor(callback: typeof visibility) {
        visibility = callback
      }
      observe() {}
    },
  }
  const originals = Object.keys(replacements).map(
    key => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const
  )
  jest.useFakeTimers()
  try {
    for (const [key, value] of Object.entries(replacements))
      Object.defineProperty(globalThis, key, { configurable: true, value })
    mountPhoneSequence(preview as unknown as HTMLElement)
    jest.advanceTimersByTime(8000)
    expect(caption.textContent).toBe('Today')
    expect(video.src).toBe('')
    visibility([{ isIntersecting: true }])
    jest.advanceTimersByTime(3999)
    expect(caption.textContent).toBe('Today')
    jest.advanceTimersByTime(1)
    expect(caption.textContent).toBe('Quran')
    toggle.click()
    jest.advanceTimersByTime(8000)
    expect(caption.textContent).toBe('Quran')
    toggle.click()
    jest.advanceTimersByTime(4000)
    expect(video.src).toBe('/sky.webm')
    expect(video.paused).toBe(false)
    document.hidden = true
    document.dispatchEvent(new Event('visibilitychange'))
    expect(video.paused).toBe(true)
    jest.advanceTimersByTime(30000)
    expect(caption.textContent).toBe('Sky')
    document.hidden = false
    document.dispatchEvent(new Event('visibilitychange'))
    expect(video.paused).toBe(false)
    visibility([{ isIntersecting: false }])
    expect(video.paused).toBe(true)
    visibility([{ isIntersecting: true }])
    video.currentTime = 15
    video.dispatchEvent(new Event('ended'))
    expect(caption.textContent).toBe('Today')
    expect(video.currentTime).toBe(15)
    motion.matches = true
    motion.dispatchEvent(new Event('change'))
    jest.advanceTimersByTime(8000)
    expect(caption.textContent).toBe('Today')
    expect(toggle.disabled).toBe(true)
    next.click()
    expect(caption.textContent).toBe('Quran')
    next.click()
    expect(video.paused).toBe(true)
    expect(video.currentTime).toBe(0)
    motion.matches = false
    motion.dispatchEvent(new Event('change'))
    toggle.click()
    jest.advanceTimersByTime(25000)
    expect(caption.textContent).toBe('Today')
    quran.dispatchEvent(new Event('error'))
    today.dispatchEvent(new Event('error'))
    expect(caption.textContent).toBe('Unavailable')
    expect(next.disabled).toBe(true)
  } finally {
    jest.clearAllTimers()
    jest.useRealTimers()
    for (const [key, descriptor] of originals) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor)
      else Reflect.deleteProperty(globalThis, key)
    }
  }
})
