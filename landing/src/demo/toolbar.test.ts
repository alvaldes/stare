import { describe, expect, it } from 'vitest'
import { TOOLS } from './model'
import { BAR_LAYOUT, HIDDEN_TOOLS, moreButton } from './toolbar'

describe('the bar a fresh install shows, as in the app', () => {
  it('keeps the drawing tools on the bar, with dividers between families', () => {
    expect(BAR_LAYOUT).toEqual(['pen', 'highlighter', '|', 'arrow', 'rectangle', 'ellipse', '|', 'text', '|', 'eraser'])
  })

  it('hides line, numbered step, blur, spotlight and laser behind the ⁞, in that order', () => {
    expect(HIDDEN_TOOLS).toEqual(['line', 'number', 'blur', 'spotlight', 'laser'])
  })

  it('places every tool exactly once', () => {
    const placed = [...BAR_LAYOUT.filter((item) => item !== '|'), ...HIDDEN_TOOLS]
    expect([...placed].sort()).toEqual(TOOLS.map((t) => t.id).sort())
  })

  it('shows the dots while the active tool is on the bar', () => {
    expect(moreButton('pen')).toEqual({ icon: 'more', label: 'More tools: Line, Numbered step, Blur, Spotlight, Laser pointer' })
  })

  it('takes the icon of an active hidden tool, so the bar always says what is armed', () => {
    expect(moreButton('blur')).toEqual({
      icon: 'blur',
      label: 'Blur is active and hidden · More tools: Line, Numbered step, Blur, Spotlight, Laser pointer',
    })
  })
})
