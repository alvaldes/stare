import { describe, expect, it } from 'vitest'
import { spotlightGradient } from './geometry'
import { resolveKey } from './keymap'
import { ERASER_RADIUS, type Point, SPOTLIGHT_DIM_ALPHA, TOOLS, type ToolId } from './model'
import { drawableMarks } from './render'
import { sampleMarks } from './samples'
import { DrawingSession } from './session'

const bare = (key: string) => ({ key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })

function drag(session: DrawingSession, tool: ToolId, from: Point, to: Point): void {
  session.begin(from, tool, 'red')
  session.extend(to)
  session.end()
}

describe('blur and spotlight, as in the app', () => {
  it('are picked with B and D and close the toolbar, after the eraser', () => {
    expect(resolveKey(bare('b'))).toEqual({ type: 'tool', tool: 'blur' })
    expect(resolveKey(bare('d'))).toEqual({ type: 'tool', tool: 'spotlight' })
    expect(TOOLS.slice(-3).map((t) => t.id)).toEqual(['eraser', 'blur', 'spotlight'])
    expect(TOOLS.find((t) => t.id === 'blur')).toEqual({ id: 'blur', name: 'Blur', key: 'B' })
    expect(TOOLS.find((t) => t.id === 'spotlight')).toEqual({ id: 'spotlight', name: 'Spotlight', key: 'D' })
  })

  it('commit a dragged rectangle and drop a stray click', () => {
    const session = new DrawingSession()
    drag(session, 'blur', { x: 10, y: 10 }, { x: 110, y: 60 })
    drag(session, 'spotlight', { x: 200, y: 200 }, { x: 201, y: 200 })
    expect(session.marks).toHaveLength(1)
    expect(session.marks[0].points).toEqual([{ x: 10, y: 10 }, { x: 110, y: 60 }])
  })

  it('are erased by touching anywhere inside their rectangle, not near it', () => {
    const session = new DrawingSession()
    drag(session, 'blur', { x: 0, y: 0 }, { x: 100, y: 50 })
    drag(session, 'spotlight', { x: 300, y: 0 }, { x: 400, y: 50 })

    expect(session.erase({ x: 50, y: 56 }, ERASER_RADIUS)).toBe(0)
    expect(session.erase({ x: 50, y: 25 }, ERASER_RADIUS)).toBe(1)
    expect(session.erase({ x: 350, y: 25 }, ERASER_RADIUS)).toBe(1)
    expect(session.marks).toEqual([])
  })

  it('mark the spotlight still being dragged, so it previews as an outline', () => {
    const session = new DrawingSession()
    drag(session, 'spotlight', { x: 0, y: 0 }, { x: 100, y: 50 })
    session.begin({ x: 200, y: 200 }, 'spotlight', 'red')
    session.extend({ x: 300, y: 260 })
    expect(drawableMarks(session).map((d) => d.inProgress)).toEqual([false, true])
  })

  it('have a sample for the shortcuts panel', () => {
    for (const tool of ['blur', 'spotlight'] as const) {
      const [mark] = sampleMarks(tool, 'red', 1)
      expect(mark.tool).toBe(tool)
      expect(mark.points).toHaveLength(2)
    }
  })
})

describe('the spotlight dim, ported from MarkRenderer.drawSpotlight', () => {
  const region = { x: 100, y: 100, width: 200, height: 100 }

  it('stays clear inside the lit ellipse and reaches the deepest dim a feather away', () => {
    const g = spotlightGradient(region, { width: 1200, height: 720 })!
    // The farthest canvas corner, in the light's own metric.
    const reach = Math.hypot((1200 - 200) / 100, (720 - 150) / 50)
    expect(g.reach).toBeCloseTo(reach)
    expect(g.stops[0]).toEqual({ offset: 0, alpha: 0 })
    expect(g.stops[1]).toEqual({ offset: 1 / reach, alpha: 0 })
    expect(g.stops[g.stops.length - 1].offset).toBeCloseTo(2.2 / reach)
    expect(g.stops[g.stops.length - 1].alpha).toBe(SPOTLIGHT_DIM_ALPHA)
  })

  it('eases the dim in with smoothstep', () => {
    const g = spotlightGradient(region, { width: 1200, height: 720 })!
    expect(g.stops.slice(2, 5).map((s) => s.alpha)).toEqual(
      [0.25, 0.5, 0.75].map((t) => SPOTLIGHT_DIM_ALPHA * t * t * (3 - 2 * t)),
    )
  })

  it('dims nothing when the region covers the whole canvas', () => {
    expect(spotlightGradient({ x: -500, y: -500, width: 2200, height: 1720 }, { width: 1200, height: 720 })).toBeNull()
  })
})
