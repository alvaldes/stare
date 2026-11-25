import { describe, expect, it } from 'vitest'
import { resolveKey } from './keymap'
import { ERASER_RADIUS, type Point, type ToolId } from './model'
import { DrawingSession } from './session'

const key = (k: string, mods: Partial<{ metaKey: boolean; ctrlKey: boolean; shiftKey: boolean }> = {}) => ({
  key: k,
  metaKey: false,
  ctrlKey: false,
  shiftKey: false,
  altKey: false,
  ...mods,
})

function draw(session: DrawingSession, tool: ToolId, from: Point, to: Point): void {
  session.begin(from, tool, 'red')
  session.extend(to)
  session.end()
}

describe('undo and redo, as in the app', () => {
  it('redoes with ⇧⌘Z', () => {
    expect(resolveKey(key('z', { metaKey: true, shiftKey: true }))).toEqual({ type: 'redo' })
    expect(resolveKey(key('Z', { ctrlKey: true, shiftKey: true }))).toEqual({ type: 'redo' })
  })

  it('puts back what undo took, in order', () => {
    const session = new DrawingSession()
    draw(session, 'line', { x: 0, y: 0 }, { x: 100, y: 0 })
    draw(session, 'line', { x: 0, y: 50 }, { x: 100, y: 50 })
    const [first, second] = session.marks

    session.undo()
    session.undo()
    expect(session.marks).toEqual([])
    session.redo()
    expect(session.marks).toEqual([first])
    session.redo()
    expect(session.marks).toEqual([first, second])
  })

  it('brings back everything Esc cleared with ⌘Z, and ⇧⌘Z clears it again', () => {
    const session = new DrawingSession()
    draw(session, 'line', { x: 0, y: 0 }, { x: 100, y: 0 })
    draw(session, 'rectangle', { x: 0, y: 50 }, { x: 100, y: 90 })
    const before = [...session.marks]

    session.clear()
    expect(session.marks).toEqual([])
    session.undo()
    expect(session.marks).toEqual(before)
    session.redo()
    expect(session.marks).toEqual([])
  })

  it('adds no step when Esc clears an empty screen', () => {
    const session = new DrawingSession()
    draw(session, 'line', { x: 0, y: 0 }, { x: 100, y: 0 })
    session.clear()
    session.clear()
    session.undo()
    expect(session.marks).toHaveLength(1)
  })

  it('forgets the redo history once a new mark or the eraser changes the screen', () => {
    const session = new DrawingSession()
    draw(session, 'line', { x: 0, y: 0 }, { x: 100, y: 0 })
    session.undo()
    draw(session, 'line', { x: 0, y: 50 }, { x: 100, y: 50 })
    session.redo()
    expect(session.marks).toHaveLength(1)

    draw(session, 'line', { x: 0, y: 100 }, { x: 100, y: 100 })
    session.undo()
    session.erase({ x: 50, y: 50 }, ERASER_RADIUS)
    session.redo()
    expect(session.marks).toEqual([])
  })

  it('skips marks the eraser already took, so undo takes back the last one still on screen', () => {
    const session = new DrawingSession()
    draw(session, 'line', { x: 0, y: 0 }, { x: 100, y: 0 })
    draw(session, 'line', { x: 0, y: 50 }, { x: 100, y: 50 })
    session.erase({ x: 50, y: 50 }, ERASER_RADIUS)
    session.undo()
    expect(session.marks).toEqual([])
  })
})
