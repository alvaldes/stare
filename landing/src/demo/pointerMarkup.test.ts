import { describe, expect, it } from 'vitest'
import { DEFAULT_POINTER, type PointerLook } from './pointer'
import { highlightMarkup, roundedSquare } from './pointerMarkup'

/** The `d` of the path painted with the glow gradient. */
function glowPath(markup: string): string {
  return markup.match(/<path d="([^"]+)" fill="url\(#/)?.[1] ?? ''
}

/** Whether the glow path sits inside the group that turns the shape. */
function glowTurnsWithShape(markup: string, degrees: number): boolean {
  const group = markup.indexOf(`<g transform="rotate(${degrees})">`)
  return group !== -1 && markup.indexOf('fill="url(#', group) > group
}

describe('pointer highlight markup, as PointerHighlightRenderer paints it', () => {
  it('clears the glow inside the rhombus hole, so the inside is a rhombus, not a circle', () => {
    const markup = highlightMarkup(DEFAULT_POINTER, 'test')
    // Radius 50, band 10% → hole 45 with the squircle's 0.62 corners.
    expect(glowPath(markup).endsWith(roundedSquare(45, 45 * 0.62))).toBe(true)
    expect(glowTurnsWithShape(markup, 45)).toBe(true)
  })

  it('cuts the squircle glow along its rounded-square hole', () => {
    const look: PointerLook = { ...DEFAULT_POINTER, preset: 'squircle' }
    expect(glowPath(highlightMarkup(look, 'test')).endsWith(roundedSquare(45, 45 * 0.62))).toBe(true)
  })

  it('cuts the ring glow along its round hole', () => {
    const look: PointerLook = { ...DEFAULT_POINTER, preset: 'ring' }
    expect(glowPath(highlightMarkup(look, 'test')).endsWith(roundedSquare(45, 45))).toBe(true)
  })

  it('starts the dot glow at its rim and the spotlight glow at its centre', () => {
    const dot = glowPath(highlightMarkup({ ...DEFAULT_POINTER, preset: 'dot' }, 'test'))
    expect(dot.endsWith(roundedSquare(50, 50))).toBe(true)
    const spot = glowPath(highlightMarkup({ ...DEFAULT_POINTER, preset: 'spotlight' }, 'test'))
    expect(spot.match(/M/g)).toHaveLength(1)
  })
})
