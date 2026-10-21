import { expect, test } from "bun:test"
import { phoneTilt } from "../src/phone-motion"

test("phone tilts down as it leaves the viewport and restores on return", () => {
  const rect = { top: 100, left: 100, width: 300, height: 600 }
  expect(phoneTilt(rect, 1000, 800)).toEqual({ scroll: -0, x: 0, y: 0 })
  expect(phoneTilt({ ...rect, top: -300 }, 1000, 800).scroll).toBe(-17.5)
  expect(phoneTilt({ ...rect, top: -900 }, 1000, 800).scroll).toBe(-35)
  expect(phoneTilt(rect, 1000, 800).scroll).toBeCloseTo(0)
})

test("mouse tilt follows physical pointer direction and stays bounded", () => {
  const rect = { top: 100, left: 100, width: 300, height: 600 }
  const centered = phoneTilt(rect, 1000, 800, { x: 250, y: 400 })
  expect(centered.x).toBeCloseTo(0)
  expect(centered.y).toBe(0)
  const bottomRight = phoneTilt(rect, 1000, 800, { x: 2000, y: 2000 })
  expect(bottomRight.x).toBe(-9)
  expect(bottomRight.y).toBe(12)
  const topLeft = phoneTilt(rect, 1000, 800, { x: -2000, y: -2000 })
  expect(topLeft.x).toBe(9)
  expect(topLeft.y).toBe(-12)
})
