import { expect, test } from 'bun:test'
import geomagnetism from 'geomagnetism'
import { androidHeading, headingError, isAligned, trueHeading, webkitHeading } from '../src/core/compass.ts'

test('Android alpha is the negated azimuth', () => {
  const event = { absolute: true, beta: 0, gamma: 0 }
  expect(androidHeading({ ...event, alpha: -Math.PI / 2 })).toBeCloseTo(90) // Facing east.
  expect(androidHeading({ ...event, alpha: Math.PI / 2 })).toBeCloseTo(270)
  expect(androidHeading({ ...event, absolute: false, alpha: 0 })).toBeNull()
  expect(androidHeading({ ...event, alpha: 0, beta: 1.2 })).toBeNull()
  expect(androidHeading({ ...event, alpha: null })).toBeNull()
})

test('WebKit headings need a good accuracy', () => {
  expect(webkitHeading(90, 10)).toBe(90)
  for (const [heading, accuracy] of [[90, -1], [90, 11], [-1, 5], [undefined, 5], [90, undefined]])
    expect(webkitHeading(heading, accuracy)).toBeNull()
})

test('declination and turn direction', () => {
  expect(trueHeading(355, 10)).toBe(5)
  expect(trueHeading(5, -10)).toBe(355)
  expect(headingError(10, 350)).toBe(20)
  expect(headingError(350, 10)).toBe(-20)
  expect([isAligned(5, false), isAligned(6, false), isAligned(8, true), isAligned(9, true)]).toEqual([true, false, true, false])
})

test('the bundled magnetic model is east-positive', () => {
  const decl = (latitude: number, longitude: number) =>
    geomagnetism.model(new Date(Date.UTC(2026, 10, 22))).point([latitude, longitude]).decl
  expect(decl(40.7128, -74.006)).toBeLessThan(-11) // New York is about 12.5° west.
  expect(decl(47.6062, -122.3321)).toBeGreaterThan(13) // Seattle is about 15° east.
})
