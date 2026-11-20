import { describe, expect, it } from 'vitest'
import { arrowHeadBarbs } from './geometry'
import { resolveKey } from './keymap'
import { DrawingSession } from './session'

const key = (k: string, mods: Partial<{ metaKey: boolean; ctrlKey: boolean; shiftKey: boolean; altKey: boolean }> = {}) => ({
  key: k,
  metaKey: false,
  ctrlKey: false,
  shiftKey: false,
  altKey: false,
  ...mods,
})

describe('keyboard shortcuts match the app', () => {
  it('selects tools with P H A L R O C', () => {
    expect(resolveKey(key('p'))).toEqual({ type: 'tool', tool: 'pen' })
    expect(resolveKey(key('h'))).toEqual({ type: 'tool', tool: 'highlighter' })
    expect(resolveKey(key('a'))).toEqual({ type: 'tool', tool: 'arrow' })
    expect(resolveKey(key('l'))).toEqual({ type: 'tool', tool: 'line' })
    expect(resolveKey(key('r'))).toEqual({ type: 'tool', tool: 'rectangle' })
    expect(resolveKey(key('o'))).toEqual({ type: 'tool', tool: 'ellipse' })
    expect(resolveKey(key('c'))).toEqual({ type: 'tool', tool: 'number' })
  })

  it('selects the eight inks with 1 through 8', () => {
    const inks = ['red', 'orange', 'yellow', 'green', 'blue', 'purple', 'white', 'black']
    inks.forEach((ink, index) => {
      expect(resolveKey(key(String(index + 1)))).toEqual({ type: 'ink', ink })
    })
    expect(resolveKey(key('9'))).toBeNull()
  })

  it('undoes with ⌘Z, clears with Esc, captures with S', () => {
    expect(resolveKey(key('z', { metaKey: true }))).toEqual({ type: 'undo' })
    expect(resolveKey(key('z', { ctrlKey: true }))).toEqual({ type: 'undo' })
    expect(resolveKey(key('Escape'))).toEqual({ type: 'clear' })
    expect(resolveKey(key('s'))).toEqual({ type: 'capture' })
  })

  it('leaves modified keys to the browser', () => {
    expect(resolveKey(key('p', { metaKey: true }))).toBeNull()
    expect(resolveKey(key('S', { shiftKey: true }))).toBeNull()
    expect(resolveKey(key('z', { metaKey: true, shiftKey: true }))).toBeNull()
    expect(resolveKey(key('z'))).toBeNull()
  })
})

describe('drawing session', () => {
  it('records a pen stroke and skips samples closer than the minimum distance', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'pen', 'red')
    session.extend({ x: 0.2, y: 0 })
    session.extend({ x: 5, y: 0 })
    session.end()
    expect(session.marks).toEqual([{ tool: 'pen', ink: 'red', points: [{ x: 0, y: 0 }, { x: 5, y: 0 }] }])
  })

  it('keeps only the start and end point for shapes', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'rectangle', 'blue')
    session.extend({ x: 10, y: 10 })
    session.extend({ x: 40, y: 30 })
    session.end()
    expect(session.marks[0].points).toEqual([{ x: 0, y: 0 }, { x: 40, y: 30 }])
  })

  it('drops a shape that never left its starting point', () => {
    const session = new DrawingSession()
    session.begin({ x: 5, y: 5 }, 'arrow', 'red')
    session.end()
    expect(session.marks).toEqual([])
  })

  it('places a numbered step on press', () => {
    const session = new DrawingSession()
    session.begin({ x: 20, y: 20 }, 'number', 'red')
    session.end()
    expect(session.marks).toHaveLength(1)
    expect(session.badgeNumber(0)).toBe(1)
  })

  it('numbers steps without gaps after an undo', () => {
    const session = new DrawingSession()
    for (const x of [10, 20, 30]) {
      session.begin({ x, y: 0 }, 'number', 'red')
      session.end()
    }
    session.undo()
    session.begin({ x: 0, y: 0 }, 'pen', 'red')
    session.extend({ x: 9, y: 9 })
    session.end()
    session.begin({ x: 40, y: 0 }, 'number', 'red')
    session.end()
    expect(session.marks.map((_, i) => session.badgeNumber(i))).toEqual([1, 2, null, 3])
  })

  it('undo removes the last mark and clear removes all of them', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'line', 'green')
    session.extend({ x: 30, y: 0 })
    session.end()
    session.begin({ x: 0, y: 10 }, 'line', 'green')
    session.extend({ x: 30, y: 10 })
    session.end()
    session.undo()
    expect(session.marks).toHaveLength(1)
    session.clear()
    expect(session.marks).toEqual([])
    expect(session.isEmpty).toBe(true)
  })

  it('exposes the stroke in progress so it can be drawn live', () => {
    const session = new DrawingSession()
    session.begin({ x: 0, y: 0 }, 'pen', 'red')
    session.extend({ x: 5, y: 5 })
    expect(session.current?.points).toHaveLength(2)
    expect(session.marks).toEqual([])
  })
})

describe('arrow head', () => {
  it('puts two barbs 16 points behind the tip at ±22.5°', () => {
    const [left, right] = arrowHeadBarbs({ x: 0, y: 0 }, { x: 100, y: 0 })
    const back = 100 - 16 * Math.cos(Math.PI / 8)
    const side = 16 * Math.sin(Math.PI / 8)
    expect(left.x).toBeCloseTo(back)
    expect(right.x).toBeCloseTo(back)
    expect(Math.abs(left.y)).toBeCloseTo(side)
    expect(left.y).toBeCloseTo(-right.y)
  })

  it('has no barbs for a zero-length arrow', () => {
    expect(arrowHeadBarbs({ x: 1, y: 1 }, { x: 1, y: 1 })).toEqual([])
  })
})
