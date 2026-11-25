import { describe, expect, it } from 'vitest'
import { resolveKey } from './keymap'
import type { MarkStyle, Point, ToolId } from './model'
import { DrawingSession } from './session'

const bare = (key: string) => ({ key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })

function drag(session: DrawingSession, tool: ToolId, style: MarkStyle, from: Point = { x: 0, y: 0 }, to: Point = { x: 120, y: 80 }) {
  session.begin(from, tool, 'red', 1, 0, style)
  session.extend(to)
  session.end()
  return session.marks[session.marks.length - 1]
}

describe('fill and arrow head keys, as in the app', () => {
  it('toggle the fill with 9 and cycle the arrow head with 0', () => {
    expect(resolveKey(bare('9'))).toEqual({ type: 'fill' })
    expect(resolveKey(bare('0'))).toEqual({ type: 'arrowHead' })
  })

  it('fill the next rectangle and ellipse, and keep the style on the mark', () => {
    const session = new DrawingSession()
    const filled: MarkStyle = { filled: true, arrowHead: 'open' }
    expect(drag(session, 'rectangle', filled).filled).toBe(true)
    expect(drag(session, 'ellipse', filled).filled).toBe(true)
    expect(drag(session, 'rectangle', { filled: false, arrowHead: 'open' }).filled).toBeUndefined()
    expect(session.marks[0].filled).toBe(true)
  })

  it('give the next arrow a solid head, and leave every other tool alone', () => {
    const session = new DrawingSession()
    const solid: MarkStyle = { filled: true, arrowHead: 'filled' }
    expect(drag(session, 'arrow', solid).arrowHead).toBe('filled')
    expect(drag(session, 'arrow', { filled: false, arrowHead: 'open' }).arrowHead).toBeUndefined()

    const line = drag(session, 'line', solid)
    expect(line.filled).toBeUndefined()
    expect(line.arrowHead).toBeUndefined()
    expect(drag(session, 'arrow', solid).filled).toBeUndefined()
  })
})
