function clamp(value: number) {
  return Math.max(-1, Math.min(1, value));
}

export function phoneTilt(
  rect: { top: number; left: number; width: number; height: number },
  viewportWidth: number,
  viewportHeight: number,
  pointer?: { x: number; y: number }
) {
  return {
    scroll: -35 * Math.max(0, Math.min(1, -rect.top / Math.max(1, rect.height))),
    x: pointer
      ? -9 * clamp((pointer.y - rect.top - rect.height / 2) / Math.max(1, viewportHeight / 2))
      : 0,
    y: pointer
      ? 12 * clamp((pointer.x - rect.left - rect.width / 2) / Math.max(1, viewportWidth / 2))
      : 0,
  }
}
