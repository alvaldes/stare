import { describe, expect, it } from 'vitest'
import {
  clickTransform,
  DEFAULT_POINTER,
  idleOpacity,
  POINTER_PRESETS,
  POINTER_SIZES,
  pointerAppearance,
  pointerInk,
  pulseScale,
} from './pointer'

describe('pointer highlight, mirrored from the app', () => {
  it('starts on the look a fresh install gets (PointerStyle.standard)', () => {
    expect(DEFAULT_POINTER).toEqual({
      preset: 'rhombus',
      size: 100,
      ink: 'purple',
      bandWidth: 0.1,
      glow: true,
      border: 'dashed',
      fadeWhenIdle: true,
      followInk: false,
      clickAnimation: 'scale',
    })
    expect(POINTER_SIZES).toContain(100)
  })

  it('offers the five shapes of Settings, in order', () => {
    expect(POINTER_PRESETS.map((p) => p.title)).toEqual(['Ring', 'Squircle', 'Rhombus', 'Dot', 'Spotlight'])
  })

  it('draws the rhombus as the squircle turned 45°, with a dashed outer line', () => {
    const a = pointerAppearance(DEFAULT_POINTER)
    expect(a.radius).toBe(50)
    expect(a.holeRadius).toBeCloseTo(45)
    expect(a.corner).toBeCloseTo(31)
    expect(a.rotation).toBe(45)
    expect(a.edgeWidth).toBe(2)
    expect(a.dash).toEqual([6, 4])
    expect(a.glowStart).toBeCloseTo(45)
    expect(a.glowRadius).toBeCloseTo(95)
  })

  it('keeps a solid line when the border is solid, and a round ring for Ring', () => {
    const a = pointerAppearance({ ...DEFAULT_POINTER, preset: 'ring', border: 'solid' })
    expect(a.dash).toBeNull()
    expect(a.corner).toBe(a.radius)
    expect(a.rotation).toBe(0)
  })

  it('fills the dot with no band or edge and starts its glow at the rim', () => {
    const a = pointerAppearance({ ...DEFAULT_POINTER, preset: 'dot' })
    expect(a.holeRadius).toBe(a.radius)
    expect(a.edgeWidth).toBe(0)
    expect(a.dash).toBeNull()
    expect(a.glowStart).toBe(a.radius)
  })

  it('draws the spotlight as glow alone, from the centre', () => {
    const a = pointerAppearance({ ...DEFAULT_POINTER, preset: 'spotlight' })
    expect(a.shape).toBe(false)
    expect(a.glowStart).toBe(0)
  })

  it('uses the app glow stops, and none when the glow is off', () => {
    expect(pointerAppearance(DEFAULT_POINTER).glowStops).toEqual([
      { offset: 0, alpha: 0.26 },
      { offset: 0.55, alpha: 0.1 },
      { offset: 1, alpha: 0 },
    ])
    expect(pointerAppearance({ ...DEFAULT_POINTER, glow: false }).glowStops).toEqual([])
  })

  it('stays fully visible for 1.2s, then fades to 25% over 0.8s', () => {
    expect(idleOpacity(0)).toBe(1)
    expect(idleOpacity(1.2)).toBe(1)
    expect(idleOpacity(1.6)).toBeCloseTo(0.625)
    expect(idleOpacity(2)).toBeCloseTo(0.25)
    expect(idleOpacity(10)).toBeCloseTo(0.25)
  })

  it('takes a fixed ink, or the active one when it follows the ink', () => {
    expect(pointerInk(DEFAULT_POINTER, 'red')).toBe('purple')
    expect(pointerInk({ ...DEFAULT_POINTER, followInk: true }, 'green')).toBe('green')
  })

  it('pulses on a click like PointerPulse: up to 1.35×, a dip to 0.94×, back to rest at 0.45s', () => {
    expect(pulseScale(0)).toBe(1)
    expect(pulseScale(0.09)).toBeCloseTo(1.35)
    expect(pulseScale(0.17)).toBeCloseTo(0.94)
    expect(pulseScale(0.17 + 0.14)).toBeCloseTo(0.97)
    expect(pulseScale(0.45)).toBe(1)
    expect(pulseScale(-0.1)).toBe(1)
  })

  it('grows on a Scale click and only turns on a Rotate click', () => {
    expect(clickTransform('scale', 0.09)).toEqual({ scale: expect.closeTo(1.35), rotation: 0 })
    const turn = clickTransform('rotate', 0.09)
    expect(turn.scale).toBe(1)
    expect(turn.rotation).toBeCloseTo((0.35 * 0.6 * 180) / Math.PI)
  })
})
