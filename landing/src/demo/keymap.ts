import { INKS, type InkId, TOOLS, type ToolId } from './model'

export type DemoAction =
  | { type: 'tool'; tool: ToolId }
  | { type: 'ink'; ink: InkId }
  | { type: 'undo' }
  | { type: 'clear' }
  | { type: 'capture' }

export interface KeyInput {
  key: string
  metaKey: boolean
  ctrlKey: boolean
  shiftKey: boolean
  altKey: boolean
}

/** Maps a key press to a demo action, using the same shortcuts as the app. */
export function resolveKey(input: KeyInput): DemoAction | null {
  const { key, metaKey, ctrlKey, shiftKey, altKey } = input

  if (key === 'Escape') return { type: 'clear' }

  if ((metaKey || ctrlKey) && !shiftKey && !altKey && key.toLowerCase() === 'z') {
    return { type: 'undo' }
  }

  // Everything else is a bare key; leave modified keys to the browser.
  if (metaKey || ctrlKey || shiftKey || altKey) return null

  const upper = key.toUpperCase()
  if (upper === 'S') return { type: 'capture' }

  const tool = TOOLS.find((t) => t.key === upper)
  if (tool) return { type: 'tool', tool: tool.id }

  const ink = INKS.find((i) => i.key === key)
  if (ink) return { type: 'ink', ink: ink.id }

  return null
}
