import { describe, expect, it } from 'vitest'
import { resolveKey } from './keymap'
import { ERASER_RADIUS, type InkId, type Point, TOOLS, type ToolId } from './model'
import { sampleMarks } from './samples'
import { DrawingSession } from './session'

const bare = (key: string) => ({ key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })

function draw(session: DrawingSession, tool: ToolId, points: Point[], ink: InkId = 'red'): void {
  session.begin(points[0], tool, ink)
  for (const p of points.slice(1)) session.extend(p)
  session.end()
}

describe('eraser, as in the app', () => {
  it('is picked with E and follows the laser in the toolbar', () => {
    expect(resolveKey(bare('e'))).toEqual({ type: 'tool', tool: 'eraser' })
    expect(TOOLS[TOOLS.findIndex((t) => t.id === 'laser') + 1]).toEqual({ id: 'eraser', name: 'Eraser', key: 'E' })
    expect(ERASER_RADIUS).toBe(8)
  })

  it('removes a whole freehand stroke when it touches any part of it', () => {
    const session = new DrawingSession()
    draw(session, 'pen', [{ x: 0, y: 0 }, { x: 50, y: 0 }, { x: 100, y: 0 }])

    expect(session.erase({ x: 75, y: 20 }, ERASER_RADIUS)).toBe(0)
    expect(session.erase({ x: 75, y: 9 }, ERASER_RADIUS)).toBe(1)
    expect(session.marks).toEqual([])
  })

  it('hits the outline of shapes, not their empty inside', () => {
    const session = new DrawingSession()
    draw(session, 'rectangle', [{ x: 0, y: 0 }, { x: 200, y: 100 }])
    draw(session, 'ellipse', [{ x: 300, y: 0 }, { x: 500, y: 100 }])

    expect(session.erase({ x: 100, y: 50 }, ERASER_RADIUS)).toBe(0)
    expect(session.erase({ x: 400, y: 50 }, ERASER_RADIUS)).toBe(0)
    expect(session.erase({ x: 100, y: 104 }, ERASER_RADIUS)).toBe(1)
    expect(session.erase({ x: 400, y: 2 }, ERASER_RADIUS)).toBe(1)
    expect(session.marks).toEqual([])
  })

  it('hits lines, arrows (head included) and badges', () => {
    const session = new DrawingSession()
    draw(session, 'line', [{ x: 0, y: 0 }, { x: 100, y: 100 }])
    draw(session, 'arrow', [{ x: 200, y: 0 }, { x: 300, y: 0 }])
    draw(session, 'number', [{ x: 500, y: 500 }])

    expect(session.erase({ x: 52, y: 48 }, ERASER_RADIUS)).toBe(1)
    // A point beside the arrow's barb, away from its shaft.
    expect(session.erase({ x: 288, y: 6 }, 2)).toBe(1)
    expect(session.erase({ x: 500 + 13 + ERASER_RADIUS - 1, y: 500 }, ERASER_RADIUS)).toBe(1)
    expect(session.marks).toEqual([])
  })

  it('erases everything under the point at once and leaves the rest', () => {
    const session = new DrawingSession()
    draw(session, 'line', [{ x: 0, y: 50 }, { x: 100, y: 50 }])
    draw(session, 'line', [{ x: 50, y: 0 }, { x: 50, y: 100 }])
    draw(session, 'line', [{ x: 0, y: 300 }, { x: 100, y: 300 }], 'blue')

    expect(session.erase({ x: 50, y: 50 }, ERASER_RADIUS)).toBe(2)
    expect(session.marks.map((m) => m.ink)).toEqual(['blue'])
  })

  it('renumbers the remaining steps without a gap', () => {
    const session = new DrawingSession()
    for (const x of [0, 100, 200]) draw(session, 'number', [{ x, y: 0 }])

    session.erase({ x: 100, y: 0 }, ERASER_RADIUS)
    expect([0, 1].map((i) => session.badgeNumber(i))).toEqual([1, 2])
  })

  it('cannot be undone: undo takes back the last mark still on screen', () => {
    const session = new DrawingSession()
    draw(session, 'line', [{ x: 0, y: 0 }, { x: 100, y: 0 }], 'red')
    draw(session, 'line', [{ x: 0, y: 200 }, { x: 100, y: 200 }], 'blue')
    session.erase({ x: 50, y: 200 }, ERASER_RADIUS)

    session.undo()
    expect(session.marks).toEqual([])
  })

  it('reaches further on heavier strokes, like the rest of the demo', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'line', 'red', 3)
    session.extend({ x: 100, y: 0 })
    session.end()

    expect(session.erase({ x: 50, y: 12 }, ERASER_RADIUS)).toBe(1)
  })

  it('has a sample that sweeps marks away', () => {
    const start = sampleMarks('eraser', 'red', 0.05)
    const end = sampleMarks('eraser', 'red', 1)
    expect(start.some((m) => m.tool === 'eraser')).toBe(true)
    expect(end.filter((m) => m.tool !== 'eraser').length).toBeLessThan(start.filter((m) => m.tool !== 'eraser').length)
  })
})
