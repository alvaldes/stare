// Example marks for the shortcuts panel: what each tool draws, at a point
// t (0 to 1) of a short drawing animation, on a 320×160 canvas.
import { ERASER_RADIUS, type InkId, type Mark, type Point, type ToolId } from './model'

export const SAMPLE_WIDTH = 320
export const SAMPLE_HEIGHT = 160

const lerp = (a: Point, b: Point, t: number): Point => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t })

/** A loose freehand loop, like circling something on screen. */
const PEN_PATH: Point[] = Array.from({ length: 48 }, (_, i) => {
  const a = -Math.PI / 2 + (i / 47) * Math.PI * 2.15
  return { x: 160 + Math.cos(a) * (92 + Math.sin(a * 3) * 6), y: 82 + Math.sin(a) * 42 }
})

const SHAPES: Partial<Record<ToolId, [Point, Point]>> = {
  highlighter: [{ x: 46, y: 58 }, { x: 236, y: 58 }],
  arrow: [{ x: 70, y: 132 }, { x: 236, y: 44 }],
  line: [{ x: 50, y: 118 }, { x: 270, y: 118 }],
  rectangle: [{ x: 62, y: 36 }, { x: 258, y: 124 }],
  ellipse: [{ x: 56, y: 32 }, { x: 264, y: 130 }],
  blur: [{ x: 60, y: 46 }, { x: 196, y: 114 }],
  spotlight: [{ x: 96, y: 34 }, { x: 224, y: 126 }],
}

/** A quick swoop across the lines, the way you sweep a laser while talking. */
const LASER_PATH: Point[] = Array.from({ length: 40 }, (_, i) => {
  const k = i / 39
  return { x: 44 + k * 232, y: 96 - Math.sin(k * Math.PI * 1.6) * 38 }
})

/** What the text sample types out, a note you might leave on a screen. */
const SAMPLE_TEXT = 'Label is cut off'

/** Three scribbles for the eraser to sweep away, left to right. */
const SCRIBBLES: Point[][] = [92, 160, 228].map((cx) =>
  Array.from({ length: 14 }, (_, i) => ({ x: cx - 26 + i * 4, y: 82 + Math.sin(i * 1.3) * 14 })),
)

const BADGES: Point[] = [{ x: 92, y: 80 }, { x: 160, y: 80 }, { x: 228, y: 80 }]

export function sampleMarks(tool: ToolId, ink: InkId, t: number): Mark[] {
  if (t <= 0) return []
  const progress = Math.min(1, t)

  if (tool === 'pen') {
    const count = Math.max(2, Math.ceil(PEN_PATH.length * progress))
    return [{ tool, ink, points: PEN_PATH.slice(0, count) }]
  }

  if (tool === 'laser') {
    const count = Math.max(2, Math.ceil(LASER_PATH.length * progress))
    return [{ tool, ink, points: LASER_PATH.slice(0, count) }]
  }

  if (tool === 'text') {
    const count = Math.max(1, Math.ceil(SAMPLE_TEXT.length * progress))
    return [{ tool, ink, points: [{ x: 60, y: 30 }], text: SAMPLE_TEXT.slice(0, count) }]
  }

  if (tool === 'eraser') {
    const reach = 40 + 236 * progress
    const remaining = SCRIBBLES.filter((s) => s[0].x > reach - ERASER_RADIUS)
    const trail = { tool, ink, points: [{ x: 40, y: 82 }, { x: reach, y: 82 }] }
    return [...remaining.map((points) => ({ tool: 'pen' as const, ink, points })), trail]
  }

  if (tool === 'number') {
    const count = Math.ceil(BADGES.length * progress)
    return BADGES.slice(0, count).map((point) => ({ tool, ink, points: [point] }))
  }

  const [start, end] = SHAPES[tool]!
  return [{ tool, ink, points: [start, lerp(start, end, progress)] }]
}
