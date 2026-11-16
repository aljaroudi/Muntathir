export function nextMediaIndex(
  current: number,
  count: number,
  failed: ReadonlySet<number>,
  direction = 1
): number {
  for (let step = 1; step <= count; step++) {
    const index = (((current + direction * step) % count) + count) % count
    if (!failed.has(index)) return index
  }
  return -1
}

export function mountPhoneSequence(preview: HTMLElement) {
  const slides = [...preview.querySelectorAll<HTMLElement>("[data-preview-slide]")]
  const video = preview.querySelector<HTMLVideoElement>("video")!
  const caption = preview.querySelector<HTMLElement>("[data-preview-caption]")!
  const controls = preview.querySelector<HTMLElement>("[data-preview-controls]")!
  const toggle = preview.querySelector<HTMLButtonElement>("[data-preview-toggle]")!
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)")
  const failed = new Set<number>()
  let current = 0
  let paused = false
  let visible = false
  let timer: ReturnType<typeof setTimeout> | undefined
  let generation = 0
  const playing = () => !paused && visible && !document.hidden && !reducedMotion.matches

  function schedule() {
    clearTimeout(timer)
    generation++
    video.pause()
    toggle.textContent =
      paused || reducedMotion.matches ? toggle.dataset.play! : toggle.dataset.pause!
    for (const button of controls.querySelectorAll<HTMLButtonElement>("button")) {
      button.disabled =
        failed.size === slides.length || (button === toggle && reducedMotion.matches)
    }
    if (!playing() || failed.size === slides.length) return
    if (slides[current] === video) {
      if (!video.hasAttribute("src")) video.src = video.dataset.src!
      const attempt = generation
      void video.play().catch(() => {
        // A pause during an outstanding play request is not a broken video.
        if (attempt === generation && playing()) fail(current)
      })
      // A stalled stream must not freeze the rest of the tour.
      timer = setTimeout(() => fail(current), 25000)
    } else {
      timer = setTimeout(() => show(nextMediaIndex(current, slides.length, failed)), 4000)
    }
  }

  function show(index: number) {
    if (index < 0) {
      caption.textContent = preview.dataset.unavailable!
      paused = true
      schedule()
      return
    }
    if (slides[index] === video && current !== index) video.currentTime = 0
    current = index
    slides.forEach((slide, i) => {
      slide.dataset.active = String(i === index)
      slide.setAttribute("aria-hidden", String(i !== index))
    })
    caption.setAttribute("aria-live", paused ? "polite" : "off")
    caption.textContent = slides[index].dataset.caption!
    schedule()
  }

  function fail(index: number) {
    failed.add(index)
    if (index === current) show(nextMediaIndex(current, slides.length, failed))
  }

  slides.forEach((slide, index) => {
    slide.addEventListener("error", () => fail(index))
    if (slide instanceof HTMLImageElement && slide.complete && !slide.naturalWidth)
      failed.add(index)
  })
  video.addEventListener("ended", () => {
    if (playing()) show(nextMediaIndex(current, slides.length, failed))
  })
  for (const direction of [-1, 1]) {
    preview
      .querySelector<HTMLButtonElement>(`[data-preview-step="${direction}"]`)!
      .addEventListener("click", () => {
        paused = true
        show(nextMediaIndex(current, slides.length, failed, direction))
      })
  }
  toggle.addEventListener("click", () => {
    paused = !paused
    schedule()
  })
  document.addEventListener("visibilitychange", schedule)
  reducedMotion.addEventListener("change", schedule)
  new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting
      schedule()
    },
    { threshold: 0.15 }
  ).observe(preview)
  controls.hidden = false
  if (failed.has(current)) show(nextMediaIndex(current, slides.length, failed))
  else schedule()
}
