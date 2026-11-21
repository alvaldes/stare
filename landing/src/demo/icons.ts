// Stroke icons on a 24×24 grid, drawn as plain path data so both the server
// (hono/jsx) and the client (hono/jsx/dom) can render them. They stand in for
// the SF Symbols the macOS toolbar uses.
import type { ToolId } from './model'

export const TOOL_ICONS: Record<ToolId, string> = {
  pen: 'M4 20l4.2-1L19 8.2 15.8 5 5 15.8 4 20zM14 6.8l3.2 3.2',
  highlighter: 'M9.5 14.5L5 19h5.5l1.8-1.8M9.5 14.5l6.3-9.3 4 3-6.3 9.3-4-3z',
  arrow: 'M6 18L18 6M10 6h8v8',
  line: 'M5 19L19 5',
  rectangle: 'M4.5 6.5h15v11h-15z',
  ellipse: 'M12 5.5c4.4 0 8 2.9 8 6.5s-3.6 6.5-8 6.5-8-2.9-8-6.5 3.6-6.5 8-6.5z',
  number: 'M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17zM10.5 9.2L12.6 8v8.2',
  eraser: 'M15.2 4.3l4.5 4.5-9.2 9.2H6.2l-2.4-2.4L15.2 4.3zM9.4 10.1l4.5 4.5M11 18h8.5',
  laser: 'M10 3.5l1.6 4.4L16 9.5l-4.4 1.6L10 15.5l-1.6-4.4L4 9.5l4.4-1.6zM17.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z',
}

export const ACTION_ICONS = {
  undo: 'M9 14L4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11',
  clear: 'M4 7h16M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5',
  capture: 'M4 8.5V5h3.5M16.5 5H20v3.5M20 15.5V19h-3.5M7.5 19H4v-3.5M12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6z',
  copy: 'M8.5 8.5h11v11h-11zM5 15.5V4.5h11',
  save: 'M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14',
} as const
