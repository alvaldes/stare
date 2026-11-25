import { describe, expect, it } from 'vitest'
import { autoDismissDelay, cardSize, evictOverflow, stackBottoms } from './card'
import { resolveKey } from './keymap'
import { TRAILING_ITEMS } from './toolbar'

describe('the capture card, as CaptureCardView draws it', () => {
  it('fits the capture in 190×126 pt with a 6 pt plate around it', () => {
    // The demo screen is 1200×720: width-bound, so 190×114.
    expect(cardSize(1200, 720)).toEqual({ width: 202, height: 126, thumbnail: { width: 190, height: 114 } })
  })

  it('never upscales a small capture and keeps a 132 pt minimum width', () => {
    expect(cardSize(60, 40)).toEqual({ width: 144, height: 52, thumbnail: { width: 60, height: 40 } })
  })

  it('leaves after 5 s, 3 s once hovered, and never while hovered or pinned', () => {
    expect(autoDismissDelay({ pinned: false, hovered: false, hasBeenHovered: false })).toBe(5000)
    expect(autoDismissDelay({ pinned: false, hovered: false, hasBeenHovered: true })).toBe(3000)
    expect(autoDismissDelay({ pinned: false, hovered: true, hasBeenHovered: true })).toBeNull()
    expect(autoDismissDelay({ pinned: true, hovered: false, hasBeenHovered: false })).toBeNull()
  })

  it('keeps at most four unpinned cards, closing the oldest unpinned first', () => {
    const cards = [
      { id: 1, pinned: true },
      { id: 2, pinned: false },
      { id: 3, pinned: false },
      { id: 4, pinned: false },
      { id: 5, pinned: false },
      { id: 6, pinned: false },
    ]
    expect(evictOverflow(cards).map((c) => c.id)).toEqual([1, 3, 4, 5, 6])
  })

  it('stacks cards up from the corner, 20 pt from the edge and 10 pt apart', () => {
    expect(stackBottoms([126, 126, 52])).toEqual([20, 156, 292])
  })
})

describe('the end of the bar, as ToolbarView lays it out', () => {
  it('ends with undo, redo, clear, done and the gripper, and has no capture button', () => {
    expect(TRAILING_ITEMS).toEqual(['undo', 'redo', 'clear', 'close', 'gripper'])
  })

  it('starts drawing again with ⌥⇧A, matched by key position since a Mac types Å', () => {
    const chord = { key: 'Å', code: 'KeyA', metaKey: false, ctrlKey: false, shiftKey: true, altKey: true }
    expect(resolveKey(chord)).toEqual({ type: 'start' })
    expect(resolveKey({ ...chord, shiftKey: false })).toBeNull()
  })
})
