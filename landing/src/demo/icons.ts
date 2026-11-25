// The SF Symbols the app's bar draws (StareCore Tool.symbolName, ToolbarView's
// action buttons and ToolbarOverflowSpec.glyph). Each one is rendered by
// AppKit at the app's size and weight into public/sf/<name>.png (4×, black
// on transparent), and the page uses it as a mask filled with currentColor,
// so it takes the button's colour like the app's template images do.
import type { ToolId } from './model'

export const TOOL_SYMBOLS: Record<ToolId, string> = {
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
}

export const ACTION_SYMBOLS = {
  undo: 'arrow.uturn.backward',
  redo: 'arrow.uturn.forward',
  clear: 'trash',
  /** "Done (esc)": leaves drawing mode. */
  close: 'xmark',
  /** Only the S keycap of the shortcuts keyboard; the bar has no capture button. */
  capture: 'camera.viewfinder',
  more: 'ellipsis',
  fill: 'square.lefthalf.filled',
  arrowHead: 'arrowtriangle.right.fill',
} as const

/** CaptureCardControlButton's symbols: 10 pt bold on its 22 pt circle. */
export const CARD_SYMBOLS = {
  pin: 'card.pin',
  pinned: 'card.pin.fill',
  close: 'card.xmark',
} as const

/** Every symbol the page uses; each must exist in public/sf. */
export const ALL_SYMBOLS: readonly string[] = [
  ...Object.values(TOOL_SYMBOLS),
  ...Object.values(ACTION_SYMBOLS),
  ...Object.values(CARD_SYMBOLS),
]

/**
 * Inline style for a symbol mask `size` pixels square. The symbol sits on a
 * 26-point canvas, so at 26 px it is exactly the size the app's bar shows.
 * Pair it with the `sf-symbol` class.
 */
export function symbolStyle(name: string, size: number | string = 26): Record<string, string> {
  const box = typeof size === 'number' ? `${size}px` : size
  const url = `url("/sf/${name}.png")`
  return { width: box, height: box, maskImage: url, webkitMaskImage: url }
}
