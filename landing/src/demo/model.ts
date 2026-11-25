// The demo's drawing vocabulary, mirrored from the macOS app (StareCore Tool,
// Ink and Stroke) so the browser behaves like the real thing.

export type ToolId =
  | 'pen'
  | 'highlighter'
  | 'arrow'
  | 'line'
  | 'rectangle'
  | 'ellipse'
  | 'text'
  | 'number'
  | 'laser'
  | 'eraser'
  | 'blur'
  | 'spotlight'

export interface ToolInfo {
  id: ToolId
  name: string
  /** Single-key shortcut, same as the app. */
  key: string
}

export const TOOLS: readonly ToolInfo[] = [
  { id: 'pen', name: 'Pen', key: 'P' },
  { id: 'highlighter', name: 'Highlighter', key: 'H' },
  { id: 'arrow', name: 'Arrow', key: 'A' },
  { id: 'line', name: 'Line', key: 'L' },
  { id: 'rectangle', name: 'Rectangle', key: 'R' },
  { id: 'ellipse', name: 'Ellipse', key: 'O' },
  { id: 'text', name: 'Text', key: 'T' },
  { id: 'number', name: 'Numbered step', key: 'C' },
  { id: 'laser', name: 'Laser pointer', key: 'F' },
  { id: 'eraser', name: 'Eraser', key: 'E' },
  { id: 'blur', name: 'Blur', key: 'B' },
  { id: 'spotlight', name: 'Spotlight', key: 'D' },
]

export type InkId = 'red' | 'orange' | 'yellow' | 'green' | 'blue' | 'purple' | 'white' | 'black'

export interface InkInfo {
  id: InkId
  name: string
  /** Digit that selects the ink, 1 through 8. */
  key: string
  hex: string
}

export const INKS: readonly InkInfo[] = [
  { id: 'red', name: 'Red', key: '1', hex: '#ff3b30' },
  { id: 'orange', name: 'Orange', key: '2', hex: '#ff9500' },
  { id: 'yellow', name: 'Yellow', key: '3', hex: '#ffcc00' },
  { id: 'green', name: 'Green', key: '4', hex: '#34c759' },
  { id: 'blue', name: 'Blue', key: '5', hex: '#007aff' },
  { id: 'purple', name: 'Purple', key: '6', hex: '#b052de' },
  { id: 'white', name: 'White', key: '7', hex: '#ffffff' },
  { id: 'black', name: 'Black', key: '8', hex: '#000000' },
]

export interface Point {
  x: number
  y: number
}

export interface Mark {
  tool: ToolId
  ink: InkId
  points: Point[]
  /**
   * Multiplier for line width and badge size. The demo screen is drawn in a
   * fixed 1200-point space, so on a narrow viewport strokes get heavier to stay
   * as visible as they are on a real display. Absent means 1.
   */
  weight?: number
  /** When a transient mark (the laser) started, in milliseconds. */
  createdAt?: number
  /** A text mark's content; its origin (points[0]) is the top-left. */
  text?: string
  /** A text mark's measured box, in screen points. */
  size?: { width: number; height: number }
  /** A rectangle or ellipse drawn with its ink wash (the app's `9`). */
  filled?: boolean
  /** An arrow drawn with the solid head (the app's `0`). */
  arrowHead?: 'filled'
}

/** How the next mark is drawn: the app's `9` and `0` toggles. */
export interface MarkStyle {
  filled: boolean
  arrowHead: 'open' | 'filled'
}

/** Stroke width in points, as in the app. */
export function lineWidth(tool: ToolId): number {
  if (tool === 'highlighter') return 18
  if (tool === 'number') return 2
  if (tool === 'text' || tool === 'eraser' || tool === 'blur') return 0
  return 3
}

/** The highlighter is translucent so the text underneath stays readable. */
export function opacity(tool: ToolId): number {
  return tool === 'highlighter' ? 0.35 : 1
}

/** The demo screen's coordinate space; marks are stored in these points. */
export const SCREEN_WIDTH = 1200
export const SCREEN_HEIGHT = 720

export const BADGE_DIAMETER = 26
export const ARROW_HEAD_LENGTH = 16
export const ARROW_HEAD_HALF_ANGLE = Math.PI / 8
export const MINIMUM_SAMPLE_DISTANCE = 0.75

/** Laser marks fade out and never appear in a capture, like the app's. */
export function isTransient(tool: ToolId): boolean {
  return tool === 'laser'
}

/** Areas, not outlines: the blur and the spotlight cover the dragged rectangle. */
export function isArea(tool: ToolId): boolean {
  return tool === 'blur' || tool === 'spotlight'
}

/** StareCore's BlurEffect.defaultRadius, in screen points. */
export const BLUR_RADIUS = 15

/** StareCore's MarkRenderer spotlight: deepest dim, feather and its eased steps. */
export const SPOTLIGHT_DIM_ALPHA = 0.55
export const SPOTLIGHT_FEATHER = 1.2
export const SPOTLIGHT_EASE_STEPS = [0.25, 0.5, 0.75]

/** The ink wash under a filled rectangle or ellipse. */
export const SHAPE_FILL_OPACITY = 0.3

/** The app's text: the regular system font at 20 points, in the ink colour. */
export const TEXT_SIZE = 20

/** Padding around a text mark's box, as StareCore's PathBuilder adds. */
export const TEXT_PADDING = 2

/** How far from the pointer the eraser reaches, in points (the app's 8). */
export const ERASER_RADIUS = 8

/** The app's default laser duration (its preference starts at 2.5 s). */
export const LASER_LIFETIME_MS = 2500

/** The whole laser stroke fades evenly, measured from its first point. */
export function laserOpacity(mark: Mark, now: number): number {
  const age = now - (mark.createdAt ?? now)
  return Math.max(0, Math.min(1, 1 - age / LASER_LIFETIME_MS))
}

export function inkHex(id: InkId): string {
  return INKS.find((ink) => ink.id === id)?.hex ?? '#ff3b30'
}
