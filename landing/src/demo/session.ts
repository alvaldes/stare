import { distance } from './geometry'
import { type InkId, isTransient, LASER_LIFETIME_MS, type Mark, MINIMUM_SAMPLE_DISTANCE, type Point, type ToolId } from './model'

const FREEHAND: ReadonlySet<ToolId> = new Set(['pen', 'highlighter', 'laser'])

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

  /** `now` stamps transient marks so they can fade; other marks ignore it. */
  begin(point: Point, tool: ToolId, ink: InkId, weight = 1, now = 0): void {
    const mark: Mark = { tool, ink, points: [point] }
    if (weight !== 1) mark.weight = weight
    if (isTransient(tool)) mark.createdAt = now
    this.current = mark
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

  /**
   * Drops lasers that have faded out. Returns whether any are still fading,
   * so the caller knows to keep redrawing.
   */
  prune(now: number): boolean {
    const alive = (m: Mark) => !isTransient(m.tool) || now - (m.createdAt ?? now) < LASER_LIFETIME_MS
    this.marks = this.marks.filter(alive)
    const fading = (m: Mark | null) => m !== null && isTransient(m.tool)
    return this.marks.some(fading) || fading(this.current)
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
