// Example marks for the shortcuts panel: what each tool draws, at a point
// t (0 to 1) of a short drawing animation, on a 320×160 canvas.
import type { InkId, Mark, Point, ToolId } from './model'

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
}

const BADGES: Point[] = [{ x: 92, y: 80 }, { x: 160, y: 80 }, { x: 228, y: 80 }]

export function sampleMarks(tool: ToolId, ink: InkId, t: number): Mark[] {
  if (t <= 0) return []
  const progress = Math.min(1, t)

  if (tool === 'pen') {
    const count = Math.max(2, Math.ceil(PEN_PATH.length * progress))
    return [{ tool, ink, points: PEN_PATH.slice(0, count) }]
  }

  if (tool === 'number') {
    const count = Math.ceil(BADGES.length * progress)
    return BADGES.slice(0, count).map((point) => ({ tool, ink, points: [point] }))
  }

  const [start, end] = SHAPES[tool]!
  return [{ tool, ink, points: [start, lerp(start, end, progress)] }]
}
