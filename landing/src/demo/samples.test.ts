import { describe, expect, it } from 'vitest'
import { TOOLS } from './model'
import { sampleMarks } from './samples'

describe('tool samples for the shortcuts panel', () => {
  it('draws nothing at the start of the animation', () => {
    for (const tool of TOOLS) expect(sampleMarks(tool.id, 'red', 0)).toEqual([])
  })

  it('draws a complete mark in the chosen ink at the end', () => {
    for (const tool of TOOLS) {
      const marks = sampleMarks(tool.id, 'blue', 1)
      expect(marks.length).toBeGreaterThan(0)
      expect(marks.some((mark) => mark.tool === tool.id)).toBe(true)
      for (const mark of marks) {
        // The eraser's sample also shows the marks it is about to sweep away.
        if (tool.id !== 'eraser') expect(mark.tool).toBe(tool.id)
        expect(mark.ink).toBe('blue')
      }
    }
  })

  it('grows freehand strokes point by point', () => {
    const half = sampleMarks('pen', 'red', 0.5)[0].points.length
    const full = sampleMarks('pen', 'red', 1)[0].points.length
    expect(half).toBeGreaterThan(1)
    expect(half).toBeLessThan(full)
  })

  it('stretches shapes from their start point', () => {
    const [start, mid] = sampleMarks('arrow', 'red', 0.5)[0].points
    const [, end] = sampleMarks('arrow', 'red', 1)[0].points
    expect(mid.x).toBeCloseTo((start.x + end.x) / 2)
    expect(mid.y).toBeCloseTo((start.y + end.y) / 2)
  })

  it('places numbered steps one after another', () => {
    expect(sampleMarks('number', 'red', 0.4)).toHaveLength(2)
    expect(sampleMarks('number', 'red', 1)).toHaveLength(3)
  })
})
