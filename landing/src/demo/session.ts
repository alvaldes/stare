import { distance } from './geometry'
import { type InkId, type Mark, MINIMUM_SAMPLE_DISTANCE, type Point, type ToolId } from './model'

const FREEHAND: ReadonlySet<ToolId> = new Set(['pen', 'highlighter'])

/** A shape shorter than this is a stray click, not a mark. */
const MINIMUM_SHAPE_LENGTH = 2

/**
 * The vector model of one drawing session: committed marks plus the stroke in
 * progress. Mirrors StareCore's DrawingSession, without any rendering.
 */
export class DrawingSession {
  marks: Mark[] = []
  current: Mark | null = null

  get isEmpty(): boolean {
    return this.marks.length === 0 && this.current === null
  }

  begin(point: Point, tool: ToolId, ink: InkId, weight = 1): void {
    this.current = weight === 1 ? { tool, ink, points: [point] } : { tool, ink, points: [point], weight }
  }

  extend(point: Point): void {
    const mark = this.current
    if (!mark || mark.tool === 'number') return

    if (FREEHAND.has(mark.tool)) {
      const last = mark.points[mark.points.length - 1]
      if (distance(last, point) >= MINIMUM_SAMPLE_DISTANCE) mark.points.push(point)
      return
    }
    mark.points = [mark.points[0], point]
  }

  end(): void {
    const mark = this.current
    this.current = null
    if (!mark) return

    const isShape = !FREEHAND.has(mark.tool) && mark.tool !== 'number'
    if (isShape) {
      const [start, end] = mark.points
      if (!end || distance(start, end) < MINIMUM_SHAPE_LENGTH) return
    }
    this.marks.push(mark)
  }

  undo(): void {
    this.marks.pop()
  }

  clear(): void {
    this.marks = []
    this.current = null
  }

  /**
   * The step number shown on a numbered badge, or null for other marks.
   * Computed from order, so undoing a step never leaves a gap.
   */
  badgeNumber(index: number): number | null {
    if (this.marks[index]?.tool !== 'number') return null
    let count = 0
    for (let i = 0; i <= index; i++) {
      if (this.marks[i].tool === 'number') count++
    }
    return count
  }
}
