import { describe, expect, it } from 'vitest'
import { resolveKey } from './keymap'
import { ERASER_RADIUS, TEXT_SIZE, TOOLS } from './model'
import { drawableMarks } from './render'
import { sampleMarks } from './samples'
import { DrawingSession } from './session'

const bare = (key: string) => ({ key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })

describe('text tool, as in the app', () => {
  it('is picked with T and sits right before numbered steps', () => {
    expect(resolveKey(bare('t'))).toEqual({ type: 'tool', tool: 'text' })
    const ids = TOOLS.map((t) => t.id)
    expect(ids.indexOf('text')).toBe(ids.indexOf('number') - 1)
    expect(TOOLS.find((t) => t.id === 'text')?.name).toBe('Text')
    expect(TOOLS.map((t) => t.key).join('')).toBe('PHALROTCFEBD')
  })

  it('places committed text at the click point in the 20 pt system size', () => {
    expect(TEXT_SIZE).toBe(20)
    const session = new DrawingSession()

    expect(session.addText({ x: 40, y: 60 }, 'Cut off here', 'blue', 120)).toBe(true)
    expect(session.marks).toEqual([
      { tool: 'text', ink: 'blue', points: [{ x: 40, y: 60 }], text: 'Cut off here', size: { width: 120, height: 20 } },
    ])
  })

  it('scales with the stroke weight on narrow screens', () => {
    const session = new DrawingSession()
    session.addText({ x: 0, y: 0 }, 'Hi', 'red', 30, 2)
    expect(session.marks[0]).toMatchObject({ weight: 2, size: { width: 30, height: 40 } })
  })

  it('never turns empty text into a mark', () => {
    const session = new DrawingSession()
    expect(session.addText({ x: 0, y: 0 }, '', 'red', 0)).toBe(false)
    expect(session.marks).toEqual([])
  })

  it('takes one undo step per text', () => {
    const session = new DrawingSession()
    session.addText({ x: 0, y: 0 }, 'One', 'red', 40)
    session.addText({ x: 0, y: 50 }, 'Two', 'red', 40)
    session.undo()
    expect(session.marks.map((m) => m.text)).toEqual(['One'])
  })

  it('is erased by touching its bounds, padded like the app', () => {
    const session = new DrawingSession()
    session.addText({ x: 100, y: 100 }, 'Label', 'red', 50)

    expect(session.erase({ x: 100 + 50 + 2 + ERASER_RADIUS + 3, y: 110 }, ERASER_RADIUS)).toBe(0)
    expect(session.erase({ x: 100 + 50 + 2 + ERASER_RADIUS - 1, y: 110 }, ERASER_RADIUS)).toBe(1)
  })

  it('stays in captures, unlike the laser', () => {
    const session = new DrawingSession()
    session.addText({ x: 0, y: 0 }, 'Keep me', 'red', 60)
    expect(drawableMarks(session, { transient: false }).map((d) => d.mark.tool)).toEqual(['text'])
  })

  it('has a sample that types itself out', () => {
    const half = sampleMarks('text', 'red', 0.5)[0].text ?? ''
    const full = sampleMarks('text', 'red', 1)[0].text ?? ''
    expect(half.length).toBeGreaterThan(0)
    expect(half.length).toBeLessThan(full.length)
    expect(full.startsWith(half)).toBe(true)
  })
})
