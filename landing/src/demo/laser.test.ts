import { describe, expect, it } from 'vitest'
import { resolveKey } from './keymap'
import { LASER_LIFETIME_MS, laserOpacity, TOOLS } from './model'
import { drawableMarks } from './render'
import { sampleMarks } from './samples'
import { DrawingSession } from './session'

const bare = (key: string) => ({ key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })

describe('laser pointer, as in the app', () => {
  it('is picked with F and sits right after numbered steps in the toolbar', () => {
    expect(resolveKey(bare('f'))).toEqual({ type: 'tool', tool: 'laser' })
    const ids = TOOLS.map((t) => t.id)
    expect(ids.indexOf('laser')).toBe(ids.indexOf('number') + 1)
    expect(TOOLS.find((t) => t.id === 'laser')?.name).toBe('Laser pointer')
  })

  it('draws freehand and remembers when it started', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'laser', 'blue', 1, 1000)
    session.extend({ x: 10, y: 0 })
    session.extend({ x: 20, y: 5 })
    session.end()

    expect(session.marks).toEqual([
      { tool: 'laser', ink: 'blue', points: [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 20, y: 5 }], createdAt: 1000 },
    ])
  })

  it('fades out evenly over 2.5 seconds from the first point', () => {
    expect(LASER_LIFETIME_MS).toBe(2500)
    const mark = { tool: 'laser' as const, ink: 'red' as const, points: [{ x: 0, y: 0 }], createdAt: 1000 }
    expect(laserOpacity(mark, 1000)).toBe(1)
    expect(laserOpacity(mark, 2250)).toBeCloseTo(0.5)
    expect(laserOpacity(mark, 3500)).toBe(0)
    expect(laserOpacity(mark, 9000)).toBe(0)
  })

  it('drops faded lasers and keeps every other mark', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'pen', 'red', 1, 0)
    session.extend({ x: 5, y: 5 })
    session.end()
    session.begin({ x: 0, y: 0 }, 'laser', 'red', 1, 0)
    session.extend({ x: 5, y: 5 })
    session.end()

    expect(session.prune(1000)).toBe(true)
    expect(session.marks.map((m) => m.tool)).toEqual(['pen', 'laser'])
    expect(session.prune(2500)).toBe(false)
    expect(session.marks.map((m) => m.tool)).toEqual(['pen'])
  })

  it('is undone like any other mark while it is still visible', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'laser', 'red', 1, 0)
    session.extend({ x: 5, y: 5 })
    session.end()
    session.undo()
    expect(session.marks).toEqual([])
  })

  it('draws under the other marks on screen and never appears in a capture', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'pen', 'red', 1, 0)
    session.extend({ x: 5, y: 5 })
    session.end()
    session.begin({ x: 0, y: 0 }, 'laser', 'red', 1, 0)
    session.extend({ x: 5, y: 5 })
    session.end()

    expect(drawableMarks(session, { now: 100 }).map((d) => d.mark.tool)).toEqual(['laser', 'pen'])
    expect(drawableMarks(session, { now: 100, transient: false }).map((d) => d.mark.tool)).toEqual(['pen'])
  })

  it('has a sample for the shortcuts panel', () => {
    const marks = sampleMarks('laser', 'green', 1)
    expect(marks).toHaveLength(1)
    expect(marks[0].points.length).toBeGreaterThan(2)
  })
})
