import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { ACTION_SYMBOLS, ALL_SYMBOLS, symbolStyle, TOOL_SYMBOLS } from './icons'
import { TOOLS } from './model'

describe('the bar draws the app’s SF Symbols', () => {
  it('uses Tool.symbolName for every tool, textformat (Aa) for text', () => {
    expect(TOOL_SYMBOLS).toEqual({
      pen: 'pencil.tip',
      highlighter: 'highlighter',
      arrow: 'arrow.up.right',
      line: 'line.diagonal',
      rectangle: 'rectangle',
      ellipse: 'circle',
      text: 'textformat',
      number: '1.circle',
      laser: 'sparkles',
      eraser: 'eraser',
      blur: 'camera.filters',
      spotlight: 'sun.max',
    })
    expect(Object.keys(TOOL_SYMBOLS).sort()).toEqual(TOOLS.map((t) => t.id).sort())
  })

  it('uses the bar’s own undo, redo, clear, done and ⁞ symbols', () => {
    expect(ACTION_SYMBOLS).toMatchObject({
      undo: 'arrow.uturn.backward',
      redo: 'arrow.uturn.forward',
      clear: 'trash',
      close: 'xmark',
      more: 'ellipsis',
    })
  })

  it('ships a rendered mask for every symbol it names', () => {
    for (const name of ALL_SYMBOLS) expect(existsSync(resolve('public/sf', `${name}.png`)), name).toBe(true)
  })

  it('masks with the symbol file at the requested size', () => {
    expect(symbolStyle('trash', 20)).toEqual({ width: '20px', height: '20px', maskImage: 'url("/sf/trash.png")', webkitMaskImage: 'url("/sf/trash.png")' })
  })
})
