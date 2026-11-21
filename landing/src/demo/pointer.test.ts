import { describe, expect, it } from 'vitest'
import { idleOpacity, POINTER_SIZES, pointerRing } from './pointer'

describe('pointer highlight, mirrored from the app', () => {
  it('offers the same sizes as the app settings', () => {
    expect(POINTER_SIZES).toEqual([32, 44, 60, 72, 80])
  })

  it('draws a band 26% of the radius with a glow out to 1.9× the radius', () => {
    const ring = pointerRing(60, 'circle')
    expect(ring.radius).toBe(30)
    expect(ring.band).toBeCloseTo(7.8)
    expect(ring.glowRadius).toBeCloseTo(57)
    expect(ring.corner).toBe(30)
  })

  it('rounds a squircle at 62% of the radius', () => {
    expect(pointerRing(60, 'squircle').corner).toBeCloseTo(18.6)
  })

  it('stays fully visible for 1.2s, then fades to 25% over 0.8s', () => {
    expect(idleOpacity(0)).toBe(1)
    expect(idleOpacity(1.2)).toBe(1)
    expect(idleOpacity(1.6)).toBeCloseTo(0.625)
    expect(idleOpacity(2)).toBeCloseTo(0.25)
    expect(idleOpacity(10)).toBeCloseTo(0.25)
  })
})
