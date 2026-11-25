import { INKS, type InkId, TOOLS, type ToolId } from './model'

export type DemoAction =
  | { type: 'tool'; tool: ToolId }
  | { type: 'ink'; ink: InkId }
  | { type: 'undo' }
  | { type: 'redo' }
  | { type: 'fill' }
  | { type: 'arrowHead' }
  | { type: 'clear' }
  | { type: 'capture' }
  /** ⌥⇧A: back into drawing mode after Done. */
  | { type: 'start' }

export interface KeyInput {
  key: string
  /** Physical key; needed for ⌥ chords, whose `key` is a special character on a Mac. */
  code?: string
  metaKey: boolean
  ctrlKey: boolean
  shiftKey: boolean
  altKey: boolean
}

/** Maps a key press to a demo action, using the same shortcuts as the app. */
export function resolveKey(input: KeyInput): DemoAction | null {
  const { key, metaKey, ctrlKey, shiftKey, altKey } = input

  if (key === 'Escape') return { type: 'clear' }

  if (altKey && shiftKey && !metaKey && !ctrlKey && input.code === 'KeyA') return { type: 'start' }

  if ((metaKey || ctrlKey) && !shiftKey && !altKey && key.toLowerCase() === 'z') {
    return { type: 'undo' }
  }

  if ((metaKey || ctrlKey) && shiftKey && !altKey && key.toLowerCase() === 'z') {
    return { type: 'redo' }
  }

  // Everything else is a bare key; leave modified keys to the browser.
  if (metaKey || ctrlKey || shiftKey || altKey) return null

  const upper = key.toUpperCase()
  if (upper === 'S') return { type: 'capture' }

  const tool = TOOLS.find((t) => t.key === upper)
  if (tool) return { type: 'tool', tool: tool.id }

  // 1–8 pick inks; the two digits left over are the app's style keys.
  if (key === '9') return { type: 'fill' }
  if (key === '0') return { type: 'arrowHead' }

  const ink = INKS.find((i) => i.key === key)
  if (ink) return { type: 'ink', ink: ink.id }

  return null
}
