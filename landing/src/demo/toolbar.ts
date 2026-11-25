// The bar a fresh install of Stare shows (StareCore ToolbarToolLayout.standard
// and ToolbarOverflowSpec), minus the pointer tool the demo does not have.
import { TOOLS, type ToolId } from './model'

/** Tools on the bar, with `|` where the app draws a family divider. */
export const BAR_LAYOUT: readonly (ToolId | '|')[] = [
  'pen',
  'highlighter',
  '|',
  'arrow',
  'rectangle',
  'ellipse',
  '|',
  'text',
  '|',
  'eraser',
]

/** What waits behind the ⁞, in the app's documented order. */
export const HIDDEN_TOOLS: readonly ToolId[] = ['line', 'number', 'blur', 'spotlight', 'laser']

const nameOf = (id: ToolId) => TOOLS.find((t) => t.id === id)?.name ?? id

/**
 * The ⁞ control: plain dots while the active tool sits on the bar, the active
 * tool's own icon while it hides here, so the bar always says what is armed.
 */
export function moreButton(active: ToolId): { icon: ToolId | 'more'; label: string } {
  const names = `More tools: ${HIDDEN_TOOLS.map(nameOf).join(', ')}`
  if (!HIDDEN_TOOLS.includes(active)) return { icon: 'more', label: names }
  return { icon: active, label: `${nameOf(active)} is active and hidden · ${names}` }
}

/** ToolbarView.trailingItems: what follows the inks. The bar has no capture button; S captures. */
export const TRAILING_ITEMS = ['undo', 'redo', 'clear', 'close', 'gripper'] as const
